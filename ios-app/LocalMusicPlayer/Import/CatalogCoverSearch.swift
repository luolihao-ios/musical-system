import Foundation
import ImageIO
import UIKit

private actor CoverLookupFailure {
    private(set) var occurred = false
    func record() { occurred = true }
}

enum CoverProvider: String, CaseIterable, Sendable {
    case netease, qq, kugou, itunes, musicbrainz, jamendo, archive
}

struct CatalogCoverCandidate: Sendable {
    let title: String
    let artist: String
    let album: String
    let imageURL: URL
    let pageURL: URL?
    let score: Int
}

// 封面不使用歌词的严格版本/时长规则；先宽搜，再按歌手和专辑排序。
enum CoverQueryPolicy {
    static func cleanedTitle(_ value: String) -> String {
        value.replacingOccurrences(of: #"[\(（\[【][^\)）\]】]*(?:live|cover|现场|翻唱|伴奏|remix|版)[^\)）\]】]*[\)）\]】]"#,
            with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func primaryArtist(_ value: String) -> String {
        let first = value.components(separatedBy: CharacterSet(charactersIn: ",，、;&／/")).first ?? ""
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return ["未知歌手", "未知艺术家", "unknown artist"].contains(trimmed.lowercased()) ? "" : trimmed
    }

    static func providerTiers(for query: MusicResourceQuery) -> [[CoverProvider]] {
        let title = cleanedTitle(query.title)
        let hasChinese = title.unicodeScalars.contains { (0x3400...0x9fff).contains($0.value) }
        let hasLatin = title.unicodeScalars.contains { (65...90).contains($0.value) || (97...122).contains($0.value) }
        let chinese = hasChinese || (!hasLatin && query.artist.unicodeScalars.contains { (0x3400...0x9fff).contains($0.value) })
        let domestic: [CoverProvider] = [.netease, .qq, .kugou]
        let foreign: [CoverProvider] = [.itunes, .musicbrainz, .jamendo, .archive]
        return chinese ? [domestic, foreign] : [foreign, domestic]
    }
    static func providers(for query: MusicResourceQuery) -> [CoverProvider] {
        providerTiers(for: query).flatMap { $0 }
    }

    static func score(title: String, artist: String, album: String, query: MusicResourceQuery, fallback: Bool) -> Int? {
        let normalize = OnlineMusicResources.normalized
        let expected = normalize(cleanedTitle(query.title))
        let actual = normalize(cleanedTitle(title))
        let singer = normalize(primaryArtist(query.artist))
        let sameArtist = !singer.isEmpty && normalize(artist).contains(singer)
        if fallback { return sameArtist ? 30 : nil }
        guard !expected.isEmpty, actual == expected || (expected.count >= 2 && actual.contains(expected)) else { return nil }
        let sameAlbum = !query.album.isEmpty && normalize(album) == normalize(query.album)
        return (actual == expected ? 100 : 60) + (sameArtist ? 30 : 0) + (sameAlbum ? 10 : 0)
    }

    static func imageURL(_ value: Any?) -> URL? {
        guard var raw = value as? String, !raw.isEmpty else { return nil }
        raw = raw.replacingOccurrences(of: "{size}", with: "500")
        if raw.hasPrefix("//") { raw = "https:" + raw }
        if raw.hasPrefix("http://") { raw = "https://" + raw.dropFirst(7) }
        guard let url = URL(string: raw), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}

actor CatalogCoverSearch: CoverArtSearching {
    static let shared = CatalogCoverSearch()
    private let transport: any CoverHTTPTransport
    private let selectedProviders: [CoverProvider]?
    private let searchWindow: TimeInterval
    private var musicBrainzSlot = Date.distantPast
    private var cooldown: [CoverProvider: Date] = [:]

    init(transport: any CoverHTTPTransport = LimitedCoverHTTPTransport(),
         providers: [CoverProvider]? = nil, searchWindow: TimeInterval = 5) {
        self.transport = transport
        self.selectedProviders = providers
        self.searchWindow = searchWindow
    }

    func isAvailable() -> Bool { true }

    func findCover(_ query: MusicResourceQuery) async throws -> CoverArtMatch? {
        guard !CoverQueryPolicy.cleanedTitle(query.title).isEmpty else { return nil }
        let started = Date()
        let deadline = started.addingTimeInterval(searchWindow)
        let failure = CoverLookupFailure()
        CoverSearchDiagnostics.log("开始 title=\(query.title) artist=\(query.artist) 顺序=\((selectedProviders ?? CoverQueryPolicy.providers(for: query)).map(\.rawValue).joined(separator: ","))")
        return try await withThrowingTaskGroup(of: CoverArtMatch?.self) { group in
            group.addTask { try await self.search(query, deadline: deadline, failure: failure) }
            group.addTask {
                // 查找目标约五秒，允许已得到候选的图片最多再收尾三秒。
                try await Task.sleep(for: .seconds(self.searchWindow + 3))
                CoverSearchDiagnostics.log("结束 reason=总预算耗尽")
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            return try await group.next() ?? nil
        }
    }

    private func search(_ query: MusicResourceQuery, deadline: Date, failure: CoverLookupFailure) async throws -> CoverArtMatch? {
        let tiers = selectedProviders.map { [$0] } ?? CoverQueryPolicy.providerTiers(for: query)
        for fallback in [false, true] {
            if fallback && CoverQueryPolicy.primaryArtist(query.artist).isEmpty { break }
            guard !Task.isCancelled, Date() < deadline else { break }
            // 优先语言的整层来源未命中后才交叉回退；每层内最多并发三个来源。
            for tier in tiers {
              for start in stride(from: 0, to: tier.count, by: 3) {
                guard !Task.isCancelled, Date() < deadline else { break }
                let batch = Array(tier[start..<min(start + 3, tier.count)])
                let match = await withTaskGroup(of: CoverArtMatch?.self, returning: CoverArtMatch?.self) { group in
                    for provider in batch {
                        group.addTask { await self.attempt(provider, query: query, fallback: fallback, deadline: deadline, failure: failure) }
                    }
                    while let result = await group.next() {
                        if let result { group.cancelAll(); return result }
                    }
                    return nil
                }
                if let match { return match }
              }
            }
        }
        CoverSearchDiagnostics.log("结束 reason=未获得可用封面或查找窗口结束")
        try Task.checkCancellation()
        let hadFailure = await failure.occurred
        if Date() >= deadline { throw URLError(.timedOut) }
        if hadFailure { throw URLError(.cannotLoadFromNetwork) }
        return nil
    }

    private func attempt(_ provider: CoverProvider, query: MusicResourceQuery, fallback: Bool, deadline: Date, failure: CoverLookupFailure) async -> CoverArtMatch? {
        guard !Task.isCancelled else { return nil }
        if let until = cooldown[provider], until > Date() {
            CoverSearchDiagnostics.log("来源=\(provider.rawValue) 跳过=服务暂时不可用，冷却中")
            await failure.record()
            return nil
        }
        do {
            let candidates = try await lookup(provider, query: query, fallback: fallback, deadline: deadline)
            CoverSearchDiagnostics.log("来源=\(provider.rawValue) 阶段=\(fallback ? "歌手专辑" : "歌名") 可用候选=\(candidates.count)")
            for candidate in candidates.sorted(by: { $0.score > $1.score }).prefix(2) {
                try Task.checkCancellation()
                guard Date() < deadline.addingTimeInterval(3) else { break }
                do {
                    let bytes = try await get(candidate.imageURL, deadline: deadline.addingTimeInterval(3), limit: 4_000_000)
                    guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceThumbnailMaxPixelSize: 800,
                            kCGImageSourceCreateThumbnailWithTransform: true
                          ] as CFDictionary), min(image.width, image.height) >= 120,
                          Double(image.width) / Double(image.height) >= 0.65,
                          Double(image.width) / Double(image.height) <= 1.55,
                          let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.88) else {
                        CoverSearchDiagnostics.log("来源=\(provider.rawValue) 图片淘汰=无法解码、尺寸或比例不合适")
                        continue
                    }
                    CoverSearchDiagnostics.log("命中 来源=\(provider.rawValue) candidate=\(candidate.title) score=\(candidate.score) 替代专辑=\(fallback)")
                    return CoverArtMatch(data: jpeg, imageURL: candidate.imageURL, pageURL: candidate.pageURL,
                        title: candidate.title, artistFallback: fallback, provider: provider.rawValue)
                } catch {
                    if Task.isCancelled { return nil }
                    CoverSearchDiagnostics.log("来源=\(provider.rawValue) 图片下载失败=\(error.localizedDescription)")
                    await failure.record()
                }
            }
        } catch {
            if !Task.isCancelled {
                await failure.record()
                CoverSearchDiagnostics.log("来源=\(provider.rawValue) 查询失败=\(error.localizedDescription)")
                if let error = error as? CoverSearchError, error == .authentication || error == .quota {
                    cooldown[provider] = Date().addingTimeInterval(300)
                }
            }
        }
        return nil
    }

    private func get(_ url: URL, deadline: Date, limit: Int = 2_000_000) async throws -> Data {
        try Task.checkCancellation()
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { throw URLError(.timedOut) }
        var request = URLRequest(url: url)
        request.timeoutInterval = min(3, remaining)
        request.setValue("AiYueCity/0.2 (https://github.com/luolihao-ios/musical-system)", forHTTPHeaderField: "User-Agent")
        let data = try await transport.data(for: request, limit: limit)
        try Task.checkCancellation()
        guard Date() < deadline else { throw URLError(.timedOut) }
        return data
    }

    private func json(_ endpoint: String, _ parameters: [String: String], deadline: Date) async throws -> [String: Any] {
        var components = URLComponents(string: endpoint)!
        if !parameters.isEmpty { components.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        let data = try await get(components.url!, deadline: deadline)
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return root }
        // QQ 可能返回 JSONP；普通 JSON 不能无条件 dropLast。
        let text = String(decoding: data, as: UTF8.self)
        if let start = text.firstIndex(of: "("), let end = text.lastIndex(of: ")"), start < end,
           let root = try? JSONSerialization.jsonObject(with: Data(text[text.index(after: start)..<end].utf8)) as? [String: Any] { return root }
        throw CoverSearchError.invalidResponse
    }

    private func lookup(_ provider: CoverProvider, query: MusicResourceQuery, fallback: Bool, deadline: Date) async throws -> [CatalogCoverCandidate] {
        let term = fallback ? CoverQueryPolicy.primaryArtist(query.artist) : CoverQueryPolicy.cleanedTitle(query.title)
        let rows: [[String: Any]]
        var candidates: [CatalogCoverCandidate] = []
        var detailFailure: (any Error)?
        func add(_ title: String, _ artist: String, _ album: String, _ image: Any?, page: String? = nil) {
            guard let score = CoverQueryPolicy.score(title: title, artist: artist, album: album, query: query, fallback: fallback),
                  let imageURL = CoverQueryPolicy.imageURL(image) else { return }
            candidates.append(CatalogCoverCandidate(title: title, artist: artist, album: album, imageURL: imageURL,
                pageURL: page.flatMap(URL.init(string:)), score: score))
        }
        switch provider {
        case .itunes:
            let root = try await json("https://itunes.apple.com/search", ["term": term, "entity": fallback ? "album" : "song", "limit": "12", "country": "US"], deadline: deadline)
            rows = root["results"] as? [[String: Any]] ?? []
            for row in rows {
                add(row["trackName"] as? String ?? row["collectionName"] as? String ?? "", row["artistName"] as? String ?? "",
                    row["collectionName"] as? String ?? "", (row["artworkUrl100"] as? String)?.replacingOccurrences(of: "100x100", with: "600x600"), page: row["collectionViewUrl"] as? String)
            }
        case .netease:
            let root = try await json("https://music.163.com/api/search/get", ["s": term, "type": "1", "limit": "12"], deadline: deadline)
            guard (root["code"] as? Int ?? 200) == 200 else { throw CoverSearchError.authentication }
            rows = (root["result"] as? [String: Any])?["songs"] as? [[String: Any]] ?? []
            let eligible = rows.filter { row in
                let artists = Self.names(row["artists"])
                return CoverQueryPolicy.score(title: row["name"] as? String ?? "", artist: artists, album: "", query: query, fallback: fallback) != nil
            }.sorted { Self.netEaseScore($0, query: query, fallback: fallback) > Self.netEaseScore($1, query: query, fallback: fallback) }
            for row in eligible.prefix(2) {
                let title = row["name"] as? String ?? ""
                let artist = Self.names(row["artists"])
                let album = row["album"] as? [String: Any] ?? [:]
                let before = candidates.count
                add(title, artist, album["name"] as? String ?? "", album["picUrl"])
                if candidates.count == before, let id = row["id"] as? Int {
                    // 搜索返回常常只有 picId。歌曲详情才有 album.picUrl，不能把缺字段当作无封面。
                    do {
                        let detail = try await json("https://music.163.com/api/song/detail/", ["id": "\(id)", "ids": "[\(id)]"], deadline: deadline)
                        for song in detail["songs"] as? [[String: Any]] ?? [] {
                            let artwork = song["album"] as? [String: Any] ?? [:]
                            add(title, artist, artwork["name"] as? String ?? "", artwork["picUrl"], page: "https://music.163.com/song?id=\(id)")
                        }
                    } catch {
                        try Task.checkCancellation()
                        CoverSearchDiagnostics.log("来源=netease 详情失败=\(error.localizedDescription) 保留已有候选=\(candidates.count)")
                        detailFailure = error
                    }
                }
            }
        case .qq:
            let root = try await json("https://c.y.qq.com/soso/fcgi-bin/client_search_cp", ["w": term, "format": "json", "p": "1", "n": "12"], deadline: deadline)
            rows = ((root["data"] as? [String: Any])?["song"] as? [String: Any])?["list"] as? [[String: Any]] ?? []
            for row in rows {
                let mid = row["albummid"] as? String ?? ""
                let image = row["picUrl"] as? String ?? (mid.isEmpty ? "" : "https://y.gtimg.cn/music/photo_new/T002R500x500M000\(mid).jpg")
                add(row["songname"] as? String ?? "", Self.names(row["singer"]), row["albumname"] as? String ?? "", image)
            }
        case .kugou:
            let root = try await json("https://mobilecdn.kugou.com/api/v3/search/song", ["keyword": term, "pagesize": "12", "page": "1"], deadline: deadline)
            rows = (root["data"] as? [String: Any])?["info"] as? [[String: Any]] ?? []
            for row in rows.prefix(5) {
                let title = row["songname"] as? String ?? "", artist = row["singername"] as? String ?? ""
                guard CoverQueryPolicy.score(title: title, artist: artist, album: "", query: query, fallback: fallback) != nil else { continue }
                let before = candidates.count
                add(title, artist, row["album_name"] as? String ?? "", row["imgurl"] ?? row["album_img"])
                if candidates.count == before, let id = row["album_id"], "\(id)" != "0" {
                    do {
                        let detail = try await json("https://mobilecdn.kugou.com/api/v3/album/info", ["albumid": "\(id)"], deadline: deadline)
                        let album = detail["data"] as? [String: Any] ?? [:]
                        add(title, artist, album["albumname"] as? String ?? "", album["imgurl"])
                    } catch {
                        try Task.checkCancellation()
                        CoverSearchDiagnostics.log("来源=kugou 详情失败=\(error.localizedDescription) 保留已有候选=\(candidates.count)")
                        detailFailure = error
                    }
                }
                if candidates.count >= 2 { break }
            }
        case .musicbrainz:
            let slot = max(Date(), musicBrainzSlot); musicBrainzSlot = slot.addingTimeInterval(1.1)
            guard slot < deadline else { return [] }
            if slot > Date() { try await Task.sleep(for: .seconds(slot.timeIntervalSinceNow)) }
            let escaped = term.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let root = try await json("https://musicbrainz.org/ws/2/recording", ["query": "\(fallback ? "artist" : "recording"):\"\(escaped)\"", "fmt": "json", "limit": "8"], deadline: deadline)
            rows = root["recordings"] as? [[String: Any]] ?? []
            for row in rows {
                let artist = Self.names(row["artist-credit"])
                for release in row["releases"] as? [[String: Any]] ?? [] {
                    guard let id = release["id"] as? String, UUID(uuidString: id) != nil else { continue }
                    add(row["title"] as? String ?? "", artist, release["title"] as? String ?? "", "https://coverartarchive.org/release/\(id)/front-500", page: "https://musicbrainz.org/release/\(id)")
                }
            }
        case .jamendo:
            let key = UserDefaults.standard.string(forKey: "jamendoClientID") ?? "709fa152"
            guard !key.isEmpty else { return [] }
            let root = try await json("https://api.jamendo.com/v3.0/tracks/", ["client_id": key, "format": "json", "limit": "10", fallback ? "artist_name" : "namesearch": term], deadline: deadline)
            if let headers = root["headers"] as? [String: Any], headers["status"] as? String == "failed" { throw CoverSearchError.authentication }
            rows = root["results"] as? [[String: Any]] ?? []
            for row in rows { add(row["name"] as? String ?? "", row["artist_name"] as? String ?? "", row["album_name"] as? String ?? "", row["album_image"] ?? row["image"], page: row["shareurl"] as? String) }
        case .archive:
            let escaped = term.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let root = try await json("https://archive.org/advancedsearch.php", ["q": "collection:jamendo-albums AND \(fallback ? "creator" : "title"):\"\(escaped)\"", "fl[]": "identifier,title,creator", "rows": "3", "output": "json"], deadline: deadline)
            rows = (root["response"] as? [String: Any])?["docs"] as? [[String: Any]] ?? []
            for row in rows.prefix(2) {
                guard let id = row["identifier"] as? String, id.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else { continue }
                let title = row["title"] as? String ?? "", artist = Self.text(row["creator"])
                guard CoverQueryPolicy.score(title: title, artist: artist, album: title, query: query, fallback: fallback) != nil else { continue }
                do {
                    let detail = try await json("https://archive.org/metadata/\(id)", [:], deadline: deadline)
                    for file in (detail["files"] as? [[String: Any]] ?? []).filter({
                        ["jpg", "jpeg", "png"].contains(URL(fileURLWithPath: $0["name"] as? String ?? "").pathExtension.lowercased())
                    }).prefix(2) {
                        guard let name = file["name"] as? String else { continue }
                        let imageURL = URL(string: "https://archive.org/download/\(id)/")!.appendingPathComponent(name)
                        add(title, artist, title, imageURL.absoluteString, page: "https://archive.org/details/\(id)")
                    }
                } catch {
                    try Task.checkCancellation()
                    CoverSearchDiagnostics.log("来源=archive 详情失败=\(error.localizedDescription) 保留已有候选=\(candidates.count)")
                    detailFailure = error
                }
            }
        }
        CoverSearchDiagnostics.log("来源=\(provider.rawValue) 返回条目=\(rows.count) 匹配并有图=\(candidates.count)")
        if candidates.isEmpty, let detailFailure { throw detailFailure }
        return candidates
    }

    private static func names(_ value: Any?) -> String {
        (value as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: ",")
    }
    private static func text(_ value: Any?) -> String { value as? String ?? (value as? [String] ?? []).joined(separator: ",") }
    private static func netEaseScore(_ row: [String: Any], query: MusicResourceQuery, fallback: Bool) -> Int {
        let album = row["album"] as? [String: Any] ?? [:]
        return CoverQueryPolicy.score(title: row["name"] as? String ?? "", artist: names(row["artists"]),
            album: album["name"] as? String ?? "", query: query, fallback: fallback) ?? -1
    }
}
