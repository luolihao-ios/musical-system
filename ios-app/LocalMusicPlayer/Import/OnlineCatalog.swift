import Foundation

enum CatalogLicense: Sendable, Equatable {
    case publicDomain
    case creativeCommons(attribution: String)
    case unknown

    var allowsDownload: Bool {
        switch self { case .publicDomain, .creativeCommons: true; case .unknown: false }
    }
    var displayName: String {
        switch self { case .publicDomain: "Public Domain"; case .creativeCommons(let value): value; case .unknown: "License unknown" }
    }
}

struct CatalogTrack: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let artist: String
    let audioURL: URL
    let license: CatalogLicense
    let provider: String
    let previewURL: URL?
    init(id: String, title: String, artist: String, audioURL: URL, license: CatalogLicense, provider: String = "", previewURL: URL? = nil) {
        self.id = id; self.title = title; self.artist = artist; self.audioURL = audioURL; self.license = license; self.provider = provider; self.previewURL = previewURL
    }
    var safeFilename: String {
        let clean = [title, artist].joined(separator: " - ").replacingOccurrences(of: "/", with: "-")
        return clean.trimmingCharacters(in: .whitespacesAndNewlines) + ".mp3"
    }
}

actor OnlineCatalog {
    static let shared = OnlineCatalog()
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func search(query: String) async throws -> [CatalogTrack] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        // Jamendo 的 client_id 是必需的。没有配置时使用无需密钥的开放许可目录。
        var results = (try? await searchInternetArchive(query: query)) ?? []
        // Jamendo 官方文档提供的只读测试 ID，用于测试构建；正式发布前替换为开发者应用 ID。
        let clientID = UserDefaults.standard.string(forKey: "jamendoClientID") ?? "709fa152"
        if !clientID.isEmpty { results.append(contentsOf: try await searchJamendo(query: query, clientID: clientID)) }
        results.append(contentsOf: await searchThirdPartyMetadata(query: query))
        return results.removingDuplicates()
    }

    private func searchJamendo(query: String, clientID: String) async throws -> [CatalogTrack] {
        var components = URLComponents(string: "https://api.jamendo.com/v3.0/tracks/")!
        components.queryItems = [URLQueryItem(name: "client_id", value: clientID), URLQueryItem(name: "format", value: "json"), URLQueryItem(name: "limit", value: "20"), URLQueryItem(name: "namesearch", value: query)]
        var request = URLRequest(url: components.url!); request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
        return try parseJamendo(data)
    }

    private struct ArchiveSearchResponse: Decodable {
        struct Response: Decodable { let docs: [ArchiveDocument] }
        let response: Response
    }

    struct ArchiveDocument: Decodable, Equatable {
        let identifier: String
        let title: String?
        let creator: String?
        let licenseurl: String?
    }

    private struct ArchiveMetadata: Decodable {
        struct Metadata: Decodable { let title: String?; let creator: String?; let licenseurl: String? }
        struct File: Decodable {
            let name: String?
            let format: String?
            let privateFile: String?
            enum CodingKeys: String, CodingKey { case name, format; case privateFile = "private" }
        }
        let metadata: Metadata?
        let files: [File]?
    }

    private func searchInternetArchive(query: String) async throws -> [CatalogTrack] {
        var components = URLComponents(string: "https://archive.org/advancedsearch.php")!
        components.queryItems = [
            // Internet Archive 中的 Jamendo 开放音乐镜像带有完整许可证和 MP3 文件元数据。
            URLQueryItem(name: "q", value: "collection:jamendo-albums AND (title:\(query) OR creator:\(query) OR description:\(query) OR subject:\(query) OR text:\(query))"),
            URLQueryItem(name: "fl[]", value: "identifier,title,creator,licenseurl"),
            URLQueryItem(name: "rows", value: "20"), URLQueryItem(name: "output", value: "json")
        ]
        var request = URLRequest(url: components.url!); request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
        let search = try JSONDecoder().decode(ArchiveSearchResponse.self, from: data)
        var tracks: [CatalogTrack] = []
        for document in search.response.docs.prefix(10) {
            guard let metadataURL = URL(string: "https://archive.org/metadata/\(document.identifier)") else { continue }
            guard let (metadataData, metadataResponse) = try? await session.data(from: metadataURL) else { continue }
            guard let metadataHTTP = metadataResponse as? HTTPURLResponse, (200..<300).contains(metadataHTTP.statusCode) else { continue }
            guard let metadata = try? JSONDecoder().decode(ArchiveMetadata.self, from: metadataData),
                  let licenseValue = metadata.metadata?.licenseurl ?? document.licenseurl,
                  let license = openLicense(from: licenseValue),
                  let file = metadata.files?.first(where: { isDownloadableAudio($0) }),
                  let filename = file.name,
                  let audioURL = URL(string: "https://archive.org/download/\(document.identifier)/\(filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename)") else { continue }
            tracks.append(CatalogTrack(id: "archive-\(document.identifier)-\(filename)", title: metadata.metadata?.title ?? document.title ?? filename, artist: metadata.metadata?.creator ?? document.creator ?? "Internet Archive", audioURL: audioURL, license: license))
        }
        return tracks
    }

    private func isDownloadableAudio(_ file: ArchiveMetadata.File) -> Bool {
        guard file.privateFile != "true", let format = file.format?.lowercased(), let name = file.name?.lowercased() else { return false }
        return (format.contains("mp3") || name.hasSuffix(".mp3")) && !name.contains("_files.xml")
    }

    private func openLicense(from value: String) -> CatalogLicense? {
        let normalized = value.lowercased()
        if normalized.contains("publicdomain") || normalized.contains("public-domain") { return .publicDomain }
        if normalized.contains("creativecommons.org") { return .creativeCommons(attribution: value) }
        return nil
    }

    private func parseJamendo(_ data: Data) throws -> [CatalogTrack] {
        struct Response: Decodable { let results: [Item] }
        struct Item: Decodable { let id: Int; let name: String; let artist_name: String; let audio: String?; let license_ccurl: String? }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.results.compactMap { item in
            guard let raw = item.audio, let url = URL(string: raw) else { return nil }
            let license: CatalogLicense = item.license_ccurl == nil ? .unknown : .creativeCommons(attribution: item.license_ccurl!)
            return CatalogTrack(id: "jamendo-\(item.id)", title: item.name, artist: item.artist_name, audioURL: url, license: license, provider: "Jamendo", previewURL: url)
        }
    }

    private func searchThirdPartyMetadata(query: String) async -> [CatalogTrack] {
        var result: [CatalogTrack] = []
        if let tracks = try? await searchNetEase(query: query) { result.append(contentsOf: tracks) }
        if let tracks = try? await searchQQMusic(query: query) { result.append(contentsOf: tracks) }
        if let tracks = try? await searchKugou(query: query) { result.append(contentsOf: tracks) }
        return result
    }

    private func requestData(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url); request.timeoutInterval = 12
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return data
    }

    private func searchNetEase(query: String) async throws -> [CatalogTrack] {
        var c = URLComponents(string: "https://music.163.com/api/search/get/web")!
        c.queryItems = [URLQueryItem(name: "s", value: query), URLQueryItem(name: "type", value: "1"), URLQueryItem(name: "limit", value: "20")]
        let object = try JSONSerialization.jsonObject(with: try await requestData(c.url!)) as? [String: Any]
        let songs = (object?["result"] as? [String: Any])?["songs"] as? [[String: Any]] ?? []
        return songs.compactMap { song in
            guard let id = song["id"] as? Int, let title = song["name"] as? String, let artists = song["artists"] as? [[String: Any]], let artist = artists.first?["name"] as? String else { return nil }
            let preview = URL(string: "https://music.163.com/song/media/outer/url?id=\(id).mp3")
            return CatalogTrack(id: "netease-\(id)", title: title, artist: artist, audioURL: preview ?? URL(string: "https://example.invalid")!, license: .unknown, provider: "网易云音乐", previewURL: preview)
        }
    }

    private func searchQQMusic(query: String) async throws -> [CatalogTrack] {
        var c = URLComponents(string: "https://c.y.qq.com/soso/fcgi-bin/client_search_cp")!
        c.queryItems = [URLQueryItem(name: "w", value: query), URLQueryItem(name: "format", value: "json"), URLQueryItem(name: "p", value: "1"), URLQueryItem(name: "n", value: "20")]
        let data = try await requestData(c.url!); let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "MusicJsonCallback(", with: "").dropLast()
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        let songs = (object?["data"] as? [String: Any])?["song"] as? [String: Any]; let list = songs?["list"] as? [[String: Any]] ?? []
        return list.compactMap { song in
            guard let id = song["songmid"] as? String, let title = song["songname"] as? String, let singers = song["singer"] as? [[String: Any]], let artist = singers.first?["name"] as? String else { return nil }
            return CatalogTrack(id: "qq-\(id)", title: title, artist: artist, audioURL: URL(string: "https://example.invalid")!, license: .unknown, provider: "QQ音乐")
        }
    }

    private func searchKugou(query: String) async throws -> [CatalogTrack] {
        var c = URLComponents(string: "https://mobilecdn.kugou.com/api/v3/search/song")!
        c.queryItems = [URLQueryItem(name: "keyword", value: query), URLQueryItem(name: "pagesize", value: "20"), URLQueryItem(name: "page", value: "1")]
        let object = try JSONSerialization.jsonObject(with: try await requestData(c.url!)) as? [String: Any]
        let list = ((object?["data"] as? [String: Any])?["info"] as? [[String: Any]]) ?? []
        return list.compactMap { song in
            guard let hash = song["hash"] as? String, let title = song["songname"] as? String else { return nil }
            return CatalogTrack(id: "kugou-\(hash)", title: title, artist: song["singername"] as? String ?? "酷狗音乐", audioURL: URL(string: "https://example.invalid")!, license: .unknown, provider: "酷狗音乐")
        }
    }

    func download(_ track: CatalogTrack, to directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard track.license.allowsDownload else { throw URLError(.userAuthenticationRequired) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(track.safeFilename)
        let (bytes, response) = try await session.bytes(for: URLRequest(url: track.audioURL))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        let expected = max(0, response.expectedContentLength); var data = Data(); data.reserveCapacity(expected > 0 ? Int(expected) : 0)
        for try await byte in bytes { data.append(byte); if expected > 0 { progress(Double(data.count) / Double(expected)) } }
        try data.write(to: destination, options: .atomic); progress(1); return destination
    }
}

private extension Array where Element == CatalogTrack {
    func removingDuplicates() -> [CatalogTrack] {
        var seen = Set<String>(); return filter { seen.insert($0.id).inserted }
    }
}
