import Foundation
import ImageIO
import StoreKit

enum CatalogLicense: Sendable, Equatable, Hashable, Codable {
    case publicDomain
    case creativeCommons(attribution: String)
    case unknown

    var allowsDownload: Bool {
        switch self { case .publicDomain, .creativeCommons: true; case .unknown: false }
    }
    var displayName: String {
        switch self { case .publicDomain: String(localized: "Public Domain"); case .creativeCommons(let value): value; case .unknown: String(localized: "License unknown") }
    }
}

struct CatalogTrack: Identifiable, Sendable, Equatable, Hashable, Codable {
    let id: String
    let title: String
    let artist: String
    let audioURL: URL
    let license: CatalogLicense
    let provider: String
    let previewURL: URL?
    let artworkURL: URL?
    let providerAllowsDownload: Bool?
    var allowsDownload: Bool { license.allowsDownload && (providerAllowsDownload ?? (provider != "Jamendo")) }
    var isShortPreview: Bool { provider.hasPrefix("iTunes") }
    init(id: String, title: String, artist: String, audioURL: URL, license: CatalogLicense, provider: String = "", previewURL: URL? = nil, artworkURL: URL? = nil, providerAllowsDownload: Bool? = nil) {
        self.id = id; self.title = title; self.artist = artist; self.audioURL = audioURL; self.license = license; self.provider = provider; self.previewURL = previewURL; self.artworkURL = artworkURL
        self.providerAllowsDownload = providerAllowsDownload
    }
    var previewID: String { "online-preview-\(id)" }
    func previewSnapshot(artworkPath: String? = nil) -> TrackSnapshot? {
        guard let previewURL else { return nil }
        return TrackSnapshot(id: previewID, title: title, artist: artist, album: provider,
            duration: 0, sourceKind: .onlinePreview, sourceReference: previewURL.absoluteString,
            artworkReference: artworkPath)
    }
    var safeFilename: String {
        let clean = [title, artist].joined(separator: " - ").replacingOccurrences(of: "/", with: "-")
        return clean.trimmingCharacters(in: .whitespacesAndNewlines) + ".mp3"
    }
}

protocol CatalogDownloading: Sendable {
    func download(_ track: CatalogTrack, to directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL
    func downloadArtwork(_ track: CatalogTrack, to directory: URL) async throws -> URL?
}

actor OnlineCatalog: CatalogDownloading {
    static let shared = OnlineCatalog()
    private let session: URLSession
    private let iTunesStorefront: @Sendable () async -> String?
    init(session: URLSession = .shared, iTunesStorefront: @escaping @Sendable () async -> String? = {
        let storefront = await Storefront.current
        return storefront?.countryCode
    }) {
        self.session = session
        self.iTunesStorefront = iTunesStorefront
    }

    func recommendations(for market: DiscoveryMarket) async -> [CatalogTrack] {
        let clientID = UserDefaults.standard.string(forKey: "jamendoClientID") ?? ""
        async let regional = try? searchNetEase(query: market.regionalQuery)
        async let open = try? searchJamendo(query: market.openQuery, clientID: clientID)
        let (regionalTracks, openTracks) = await (regional, open)
        let openResults = openTracks ?? []
        let combined = DiscoveryModel.playableTracks(
            Array(openResults.prefix(6)) + (regionalTracks ?? []) + openResults
        )
        guard combined.isEmpty, !Task.isCancelled else { return combined }
        return (try? await searchInternetArchive(query: market.openQuery, maxDocuments: 3)) ?? []
    }

    private enum SearchSource: String, Sendable {
        case jamendo, archive, netease, qq, kugou, itunes
    }

    func suggest(query: String) async -> [String] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }
        async let netease = try? suggestNetEase(query: keyword)
        async let itunes = try? suggestITunes(query: keyword)
        let (neList, itList) = await (netease, itunes)
        let combined = (neList ?? []) + (itList ?? [])
        return Array(combined.removingDuplicateStrings().prefix(8))
    }

    private func suggestNetEase(query: String) async throws -> [String] {
        var c = URLComponents(string: "https://music.163.com/api/search/suggest/web")!
        c.queryItems = [URLQueryItem(name: "s", value: query)]
        let data = try await requestData(c.url!, timeout: 5)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any] else { return [] }
        var list: [String] = []
        if let songs = result["songs"] as? [[String: Any]] {
            for song in songs {
                guard let name = song["name"] as? String, !name.isEmpty else { continue }
                if let artists = song["artists"] as? [[String: Any]],
                   let artist = artists.first?["name"] as? String, !artist.isEmpty {
                    list.append("\(name) \(artist)")
                } else {
                    list.append(name)
                }
            }
        }
        if let artists = result["artists"] as? [[String: Any]] {
            for artist in artists {
                if let name = artist["name"] as? String, !name.isEmpty {
                    list.append(name)
                }
            }
        }
        return list
    }

    private func suggestITunes(query: String) async throws -> [String] {
        let storefront = await iTunesStorefront()
        let primary = Self.iTunesRegion(storefront: storefront, locale: .current)
        let region = primary == "CN" ? "HK" : primary
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [
            .init(name: "term", value: query), .init(name: "country", value: region),
            .init(name: "media", value: "music"), .init(name: "entity", value: "song"),
            .init(name: "limit", value: "5")
        ]
        guard let url = c.url else { return [] }
        let tracks = try Self.decodeITunesTracks(try await requestData(url, timeout: 5), region: region)
        return tracks.map { "\($0.title) \($0.artist)" }
    }

    func search(query: String, onUpdate: (@MainActor @Sendable ([CatalogTrack]) -> Void)? = nil) async throws -> [CatalogTrack] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }
        let clientID = UserDefaults.standard.string(forKey: "jamendoClientID") ?? ""
        let sources: [SearchSource] = (clientID.isEmpty ? [] : [.jamendo]) + [.archive, .netease, .qq, .kugou, .itunes]
        let completed = await withTaskGroup(of: (SearchSource, [CatalogTrack]?).self) { group in
            for source in sources {
                group.addTask { (source, await self.searchSource(source, query: keyword, clientID: clientID)) }
            }
            var results: [SearchSource: [CatalogTrack]] = [:]
            for await (source, tracks) in group {
                guard !Task.isCancelled else { group.cancelAll(); break }
                guard let tracks else { continue }
                results[source] = tracks
                if let onUpdate {
                    let visible = Self.prioritizePlayable(sources.flatMap { results[$0] ?? [] })
                    await onUpdate(visible)
                }
            }
            return results
        }
        try Task.checkCancellation()
        guard !completed.isEmpty else { throw URLError(.cannotLoadFromNetwork) }
        return Self.prioritizePlayable(sources.flatMap { completed[$0] ?? [] })
    }

    func similarTracks(to track: TrackSnapshot, excluding existingIDs: Set<String>) async -> [CatalogTrack] {
        let trimmedArtist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let isGenericArtist = trimmedArtist.isEmpty || trimmedArtist == "爱乐之城" || trimmedArtist == "Internet Archive" || trimmedArtist == "酷狗音乐"
        let hasCJK = (track.title + trimmedArtist).unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF }
        let primaryQuery = isGenericArtist ? (hasCJK ? "热门华语" : "acoustic") : trimmedArtist
        let secondaryQuery = hasCJK ? "华语流行" : "piano"

        var candidates: [CatalogTrack] = []
        if let firstBatch = try? await searchNetEase(query: primaryQuery) {
            candidates.append(contentsOf: firstBatch)
        }
        if candidates.filter({ $0.previewURL != nil && !existingIDs.contains($0.previewID) }).count < 5 {
            if let secondBatch = try? await searchNetEase(query: secondaryQuery) {
                candidates.append(contentsOf: secondBatch)
            }
        }
        if candidates.filter({ $0.previewURL != nil && !existingIDs.contains($0.previewID) }).count < 4 {
            let clientID = UserDefaults.standard.string(forKey: "jamendoClientID") ?? ""
            if let jamendo = try? await searchJamendo(query: primaryQuery, clientID: clientID) {
                candidates.append(contentsOf: jamendo)
            }
            if let itunes = try? await searchITunes(query: primaryQuery) {
                candidates.append(contentsOf: itunes)
            }
        }

        let unique = candidates.removingDuplicates().filter { candidate in
            guard let url = candidate.previewURL,
                  url.scheme?.lowercased() == "https",
                  !(url.host ?? "").lowercased().hasSuffix(".invalid") else {
                return false
            }
            return !existingIDs.contains(candidate.previewID)
        }
        let fullLengthFirst = unique.filter { !$0.isShortPreview } + unique.filter(\.isShortPreview)
        return Array(fullLengthFirst.prefix(10))
    }

    func resolveFreshPlayableTrack(title: String, artist: String) async -> CatalogTrack? {
        let keyword = [title, artist]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !keyword.isEmpty else { return nil }
        if let netease = try? await searchNetEase(query: keyword),
           let first = netease.first(where: { $0.previewURL != nil }) {
            return first
        }
        if let itunes = try? await searchITunes(query: keyword),
           let first = itunes.first(where: { $0.previewURL != nil }) {
            return first
        }
        return nil
    }

    private func searchSource(_ source: SearchSource, query: String, clientID: String) async -> [CatalogTrack]? {
        do {
            let tracks: [CatalogTrack]
            switch source {
            case .jamendo: tracks = try await searchJamendo(query: query, clientID: clientID)
            case .archive: tracks = try await searchInternetArchive(query: query)
            case .netease: tracks = try await searchNetEase(query: query)
            case .qq: tracks = try await searchQQMusic(query: query)
            case .kugou: tracks = try await searchKugou(query: query)
            case .itunes: tracks = try await searchITunes(query: query)
            }
            PlayerInteractionDiagnostics.log("online-search source=\(source.rawValue) accepted=\(tracks.count) playable=\(tracks.filter { $0.previewURL != nil }.count)")
            return tracks
        } catch {
            if !Task.isCancelled {
                let nsError = error as NSError
                PlayerInteractionDiagnostics.log("online-search source=\(source.rawValue) error=\(nsError.domain):\(nsError.code)")
            }
            return nil
        }
    }

    nonisolated static func prioritizePlayable(_ tracks: [CatalogTrack]) -> [CatalogTrack] {
        let unique = tracks.removingDuplicates()
        var artworkByTitle: [String: URL] = [:]
        for track in unique {
            if let art = track.artworkURL {
                let key = track.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty && artworkByTitle[key] == nil {
                    artworkByTitle[key] = art
                }
            }
        }
        let enriched = unique.map { track -> CatalogTrack in
            guard track.artworkURL == nil else { return track }
            let key = track.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard let art = artworkByTitle[key] else { return track }
            return CatalogTrack(
                id: track.id, title: track.title, artist: track.artist,
                audioURL: track.audioURL, license: track.license, provider: track.provider,
                previewURL: track.previewURL, artworkURL: art,
                providerAllowsDownload: track.providerAllowsDownload
            )
        }
        return enriched.filter { $0.previewURL != nil } + enriched.filter { $0.previewURL == nil }
    }

    nonisolated static func iTunesRegion(storefront: String?, locale: Locale) -> String {
        let alpha2 = [
            "USA": "US", "CHN": "CN", "TWN": "TW", "HKG": "HK", "MAC": "MO",
            "GBR": "GB", "CAN": "CA", "AUS": "AU", "NZL": "NZ", "JPN": "JP",
            "KOR": "KR", "SGP": "SG", "MYS": "MY", "THA": "TH", "VNM": "VN",
            "IDN": "ID", "PHL": "PH", "IND": "IN", "FRA": "FR", "DEU": "DE",
            "ESP": "ES", "ITA": "IT", "NLD": "NL", "BEL": "BE", "CHE": "CH",
            "SWE": "SE", "NOR": "NO", "DNK": "DK", "FIN": "FI", "IRL": "IE",
            "BRA": "BR", "MEX": "MX", "ZAF": "ZA", "ARE": "AE", "SAU": "SA"
        ]
        for value in [storefront, locale.region?.identifier].compactMap({ $0?.uppercased() }) {
            if let mapped = alpha2[value] { return mapped }
            if value.utf8.count == 2 && value.utf8.allSatisfy({ (65...90).contains($0) }) { return value }
        }
        return "US"
    }

    private func searchITunes(query: String) async throws -> [CatalogTrack] {
        let storefront = await iTunesStorefront()
        let primary = Self.iTunesRegion(storefront: storefront, locale: .current)
        let regions: [String] = primary == "CN" ? ["CN", "HK", "US"] : [primary, "US"].removingDuplicateStrings()
        for region in regions {
            var components = URLComponents(string: "https://itunes.apple.com/search")!
            components.queryItems = [
                .init(name: "term", value: query), .init(name: "country", value: region),
                .init(name: "media", value: "music"), .init(name: "entity", value: "song"),
                .init(name: "limit", value: "20")
            ]
            guard let url = components.url else { continue }
            guard let data = try? await requestData(url, timeout: 8),
                  let results = try? Self.decodeITunesTracks(data, region: region),
                  !results.isEmpty else { continue }
            PlayerInteractionDiagnostics.log("online-search itunes region=\(region) tracks=\(results.count)")
            return results
        }
        return []
    }

    nonisolated static func decodeITunesTracks(_ data: Data, region: String) throws -> [CatalogTrack] {
        struct Response: Decodable {
            struct Item: Decodable {
                let kind: String?
                let trackId: Int?
                let trackName: String?
                let artistName: String?
                let artworkUrl100: String?
                let previewUrl: String?
            }
            let results: [Item]
        }
        return try JSONDecoder().decode(Response.self, from: data).results.compactMap { item in
            guard item.kind == "song", let id = item.trackId,
                  let title = item.trackName, !title.isEmpty,
                  let artist = item.artistName, !artist.isEmpty else { return nil }
            let preview = item.previewUrl.flatMap { value -> URL? in
                guard let url = URL(string: value), url.scheme?.lowercased() == "https" else { return nil }
                return url
            }
            let artwork = item.artworkUrl100.flatMap { raw -> URL? in
                let upgraded = raw.replacingOccurrences(of: "100x100", with: "600x600")
                return URL(string: upgraded)
            }
            return CatalogTrack(
                id: "itunes-\(region)-\(id)",
                title: title,
                artist: artist,
                audioURL: preview ?? URL(string: "https://example.invalid")!,
                license: .unknown,
                provider: "iTunes · \(region)",
                previewURL: preview,
                artworkURL: artwork,
                providerAllowsDownload: false
            )
        }
    }

    private func searchJamendo(query: String, clientID: String) async throws -> [CatalogTrack] {
        guard !clientID.isEmpty else { return [] }
        var components = URLComponents(string: "https://api.jamendo.com/v3.0/tracks/")!
        components.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "format", value: "json"),
            .init(name: "limit", value: "20"), .init(name: "search", value: query),
            .init(name: "type", value: "single albumtrack"), .init(name: "imagesize", value: "500")
        ]
        var request = URLRequest(url: components.url!); request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
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
            let title: String?
            let source: String?
            let privateFile: String?
            enum CodingKeys: String, CodingKey { case name, format, title, source; case privateFile = "private" }
        }
        let metadata: Metadata?
        let files: [File]?
    }

    enum ArchiveOrder: Sendable { case relevance, popular, recent }

    nonisolated static func archiveQuery(query: String?, order: ArchiveOrder, limit: Int) -> [URLQueryItem] {
        let terms = (query ?? "").split { !$0.isLetter && !$0.isNumber }.prefix(8).joined(separator: " ")
        let match = terms.isEmpty ? "" : " AND (title:\"\(terms)\" OR creator:\"\(terms)\" OR description:\"\(terms)\" OR subject:\"\(terms)\")"
        let licensed = order == .relevance ? "" : " AND (licenseurl:*creativecommons.org* OR licenseurl:*publicdomain*)"
        var items = [URLQueryItem(name: "q", value: "collection:jamendo-albums" + licensed + match),
                     URLQueryItem(name: "rows", value: String(limit)), URLQueryItem(name: "output", value: "json")]
        items += ["identifier", "title", "creator", "licenseurl"].map { URLQueryItem(name: "fl[]", value: $0) }
        switch order {
        case .relevance: break
        case .popular: items.append(.init(name: "sort[]", value: "downloads desc"))
        case .recent: items.append(.init(name: "sort[]", value: "publicdate desc"))
        }
        return items
    }

    func discoveryFeed(for market: DiscoveryMarket) async -> DiscoveryFeed {
        let isChineseMarket = ["CN", "TW", "HK", "MO"].contains(market.region.uppercased())
        let clientID = UserDefaults.standard.string(forKey: "jamendoClientID") ?? ""

        if isChineseMarket {
            async let hot = try? searchNetEase(query: "热门华语")
            async let calm = try? searchNetEase(query: market.regionalQuery)
            async let folk = try? searchNetEase(query: "民谣")
            async let piano = try? searchNetEase(query: "钢琴曲")
            async let itunesHits = try? searchITunes(query: "周杰伦")
            async let openFallback = try? archiveGroups(query: nil, order: .popular, limit: 5)
            let (hotTracks, calmTracks, folkTracks, pianoTracks, itunesTracks, archiveAlbums) = await (hot, calm, folk, piano, itunesHits, openFallback)

            let chartTracks = DiscoveryModel.playableTracks((hotTracks ?? []) + (itunesTracks ?? []))
            let calmList = DiscoveryModel.playableTracks(calmTracks ?? [])
            let folkList = DiscoveryModel.playableTracks(folkTracks ?? [])
            let pianoList = DiscoveryModel.playableTracks(pianoTracks ?? [])
            let itunesList = DiscoveryModel.playableTracks(itunesTracks ?? [])
            let albums = archiveAlbums ?? []

            let mixes: [DiscoveryGroup] = [
                .init(id: "calm", title: "轻松时刻", tracks: calmList),
                .init(id: "folk", title: "民谣精选", tracks: folkList),
                .init(id: "piano", title: "钢琴漫游", tracks: pianoList),
                .init(id: "itunes-picks", title: "华语精选", tracks: itunesList)
            ]
            let radios: [DiscoveryGroup] = [
                .init(id: "radio-calm", title: "轻松时刻", tracks: calmList + pianoList),
                .init(id: "radio-hot", title: "华语热播", tracks: chartTracks),
                .init(id: "radio-folk", title: "民谣电台", tracks: folkList)
            ]
            let combinedRecs = DiscoveryModel.playableTracks(
                Array(itunesList.prefix(4)) + Array(chartTracks.prefix(6)) + Array(calmList.prefix(4)) + Array(folkList.prefix(4))
            )
            if !combinedRecs.isEmpty {
                return DiscoveryFeed(recommendations: combinedRecs, shelves: [
                    .init(id: "chart", title: "热门榜单", groups: [.init(id: "popular", title: "热门华语", tracks: chartTracks)]),
                    .init(id: "mixes", title: "精选歌单", groups: mixes),
                    .init(id: "radio", title: "风格电台", groups: radios),
                    .init(id: "recent", title: "最近收录", groups: [.init(id: "newest", title: "轻音乐精选", tracks: pianoList)]),
                    .init(id: "albums", title: "热门专辑", groups: albums)
                ]).filtered()
            }
        }

        async let jamendoOpen = try? searchJamendo(query: market.openQuery, clientID: clientID)
        async let popular = try? archiveGroups(query: nil, order: .popular, limit: 8)
        async let recent = try? archiveGroups(query: nil, order: .recent, limit: 5)
        async let gentle = try? archiveGroups(query: market.openQuery, order: .popular, limit: 4)
        async let electronic = try? archiveGroups(query: "electronic", order: .popular, limit: 4)
        async let jazz = try? archiveGroups(query: "jazz", order: .popular, limit: 4)
        let (jamendoResult, topResult, freshResult, calmResult, electroResult, swingResult) = await (jamendoOpen, popular, recent, gentle, electronic, jazz)
        let jamendo = DiscoveryModel.playableTracks(jamendoResult ?? [])
        let top = topResult ?? [], fresh = freshResult ?? [], calm = calmResult ?? []
        let electro = electroResult ?? [], swing = swingResult ?? []
        let chart = top.compactMap { $0.tracks.first }
        let newest = fresh.compactMap { $0.tracks.first }
        let mixes: [DiscoveryGroup] = [
            .init(id: "calm", title: "轻松时刻", tracks: Array(jamendo.prefix(6)) + calm.compactMap { $0.tracks.first }),
            .init(id: "electronic", title: "电子节拍", tracks: electro.compactMap { $0.tracks.first }),
            .init(id: "jazz", title: "爵士漫游", tracks: swing.compactMap { $0.tracks.first })
        ]
        let radios: [DiscoveryGroup] = [
            .init(id: "radio-calm", title: "轻松时刻", tracks: jamendo + calm.flatMap(\.tracks)),
            .init(id: "radio-electronic", title: "电子节拍", tracks: electro.flatMap(\.tracks)),
            .init(id: "radio-jazz", title: "爵士漫游", tracks: swing.flatMap(\.tracks))
        ]
        return DiscoveryFeed(recommendations: Array(jamendo.prefix(6)) + Array(mixes.flatMap(\.tracks).prefix(8)) + chart + newest, shelves: [
            .init(id: "chart", title: "热门榜单", groups: [.init(id: "popular", title: "档案馆热门", tracks: chart)]),
            .init(id: "mixes", title: "精选歌单", groups: mixes),
            .init(id: "radio", title: "风格电台", groups: radios),
            .init(id: "recent", title: "最近收录", groups: [.init(id: "newest", title: "最近收录", tracks: newest)]),
            .init(id: "albums", title: "热门专辑", groups: top)
        ]).filtered()
    }

    private func searchInternetArchive(query: String, maxDocuments: Int = 10) async throws -> [CatalogTrack] {
        let groups = try await archiveGroups(query: query, order: .relevance, limit: maxDocuments, trackLimit: nil)
        return Self.archiveSearchTracks(in: groups, query: query)
    }

    nonisolated static func archiveSearchTracks(in groups: [DiscoveryGroup], query: String) -> [CatalogTrack] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = groups.flatMap(\.tracks).filter { !term.isEmpty && $0.title.localizedStandardContains(term) }
        return Array((matches.isEmpty ? groups.compactMap { $0.tracks.first } : matches).prefix(20))
    }

    private func archiveGroups(query: String?, order: ArchiveOrder, limit: Int, trackLimit: Int? = 12) async throws -> [DiscoveryGroup] {
        var components = URLComponents(string: "https://archive.org/advancedsearch.php")!
        components.queryItems = Self.archiveQuery(query: query, order: order, limit: limit)
        guard let url = components.url else { throw URLError(.badURL) }
        let data = try await requestData(url)
        let search = try JSONDecoder().decode(ArchiveSearchResponse.self, from: data)
        return await withTaskGroup(of: (Int, DiscoveryGroup?).self) { tasks in
            for (index, document) in search.response.docs.prefix(limit).enumerated() {
                tasks.addTask { (index, await self.archiveGroup(document, trackLimit: trackLimit)) }
            }
            var results: [(Int, DiscoveryGroup)] = []
            for await (index, group) in tasks { if let group { results.append((index, group)) } }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func archiveGroup(_ document: ArchiveDocument, trackLimit: Int?) async -> DiscoveryGroup? {
        guard !Task.isCancelled,
              document.identifier.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil,
              let metadataURL = URL(string: "https://archive.org/metadata/\(document.identifier)"),
              let data = try? await requestData(metadataURL),
              let metadata = try? JSONDecoder().decode(ArchiveMetadata.self, from: data),
              let licenseValue = metadata.metadata?.licenseurl ?? document.licenseurl,
              let license = openLicense(from: licenseValue) else { return nil }
        let album = metadata.metadata?.title ?? document.title ?? document.identifier
        let artist = metadata.metadata?.creator ?? document.creator ?? "Internet Archive"
        let cover = URL(string: "https://archive.org/services/img/\(document.identifier)")
        let files = (metadata.files ?? []).filter(isDownloadableAudio)
        let originals = files.filter { $0.source == "original" }
        let candidates = originals.isEmpty ? files : originals
        let tracks = candidates.prefix(trackLimit ?? candidates.count).compactMap { file -> CatalogTrack? in
            guard let filename = file.name, let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let audio = URL(string: "https://archive.org/download/\(document.identifier)/\(encoded)") else { return nil }
            let title = file.title ?? (filename as NSString).deletingPathExtension
            return CatalogTrack(id: "archive-\(document.identifier)-\(filename)", title: title, artist: artist,
                audioURL: audio, license: license, provider: "Internet Archive", previewURL: audio, artworkURL: cover)
        }
        return tracks.isEmpty ? nil : .init(id: document.identifier, title: album, tracks: tracks)
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

    func parseJamendo(_ data: Data) throws -> [CatalogTrack] {
        struct ProviderID: Decodable {
            let value: String
            init(from decoder: Decoder) throws {
                let box = try decoder.singleValueContainer()
                if let id = try? box.decode(String.self) { value = id }
                else { value = String(try box.decode(Int.self)) }
            }
        }
        struct Response: Decodable {
            struct Headers: Decodable { let status: String? }
            let headers: Headers?
            let results: [Item]
        }
        struct Item: Decodable {
            let id: ProviderID; let name: String; let artist_name: String
            let audio: String?; let license_ccurl: String?; let image: String?; let album_image: String?
            let audiodownload: String?; let audiodownload_allowed: Bool?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        if let status = response.headers?.status, status != "success" { throw URLError(.badServerResponse) }
        return response.results.compactMap { item in
            let id = item.id.value
            guard !id.isEmpty, let url = httpsURL(item.audio) else { return nil }
            let license = item.license_ccurl.flatMap { openLicense(from: $0) } ?? .unknown
            let download = item.audiodownload_allowed == true ? httpsURL(item.audiodownload) : nil
            return CatalogTrack(id: "jamendo-\(id)", title: item.name, artist: item.artist_name,
                audioURL: download ?? url, license: license, provider: "Jamendo", previewURL: url,
                artworkURL: httpsURL(item.image) ?? httpsURL(item.album_image), providerAllowsDownload: download != nil)
        }
    }

    private func httpsURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    private func requestData(_ url: URL, timeout: TimeInterval = 12) async throws -> Data {
        var request = URLRequest(url: url); request.timeoutInterval = timeout
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return data
    }

    private func searchNetEase(query: String) async throws -> [CatalogTrack] {
        var c = URLComponents(string: "https://music.163.com/api/search/get/web")!
        c.queryItems = [URLQueryItem(name: "s", value: query), URLQueryItem(name: "type", value: "1"), URLQueryItem(name: "limit", value: "20")]
        let object = try JSONSerialization.jsonObject(with: try await requestData(c.url!)) as? [String: Any]
        let songs = (object?["result"] as? [String: Any])?["songs"] as? [[String: Any]] ?? []
        let parsed: [(id: Int, title: String, artist: String, fee: Int, picUrl: String?)] = songs.compactMap { song in
            guard let id = song["id"] as? Int,
                  let title = song["name"] as? String,
                  let artists = song["artists"] as? [[String: Any]],
                  let artist = artists.first?["name"] as? String else { return nil }
            let fee = song["fee"] as? Int ?? 0
            let picUrl = (song["album"] as? [String: Any])?["picUrl"] as? String
            return (id, title, artist, fee, picUrl)
        }
        // 优先排免费可播曲目 (fee == 0 或 8)，VIP 曲目排后。
        let ordered = parsed.filter { $0.fee == 0 || $0.fee == 8 } + parsed.filter { $0.fee != 0 && $0.fee != 8 }
        let ids = ordered.prefix(20).map(\.id)
        let artworkMap = await fetchNetEaseArtworks(ids: ids)
        return ordered.prefix(20).map { item in
            let preview = URL(string: "https://music.163.com/song/media/outer/url?id=\(item.id).mp3")
            let rawArt = artworkMap[item.id] ?? item.picUrl
            let artwork = rawArt.flatMap { value -> URL? in
                let httpsValue = value.hasPrefix("http://") ? "https://" + value.dropFirst(7) : value
                let resized = httpsValue.contains("?") ? httpsValue : httpsValue + "?param=400y400"
                return URL(string: resized)
            }
            return CatalogTrack(
                id: "netease-\(item.id)",
                title: item.title,
                artist: item.artist,
                audioURL: preview ?? URL(string: "https://example.invalid")!,
                license: .unknown,
                provider: "网易云音乐",
                previewURL: preview,
                artworkURL: artwork
            )
        }
    }

    private func fetchNetEaseArtworks(ids: [Int]) async -> [Int: String] {
        guard !ids.isEmpty else { return [:] }
        var components = URLComponents(string: "https://music.163.com/api/song/detail")!
        let idList = "[" + ids.map(String.init).joined(separator: ",") + "]"
        components.queryItems = [URLQueryItem(name: "ids", value: idList)]
        guard let url = components.url,
              let data = try? await requestData(url, timeout: 8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let songs = root["songs"] as? [[String: Any]] else { return [:] }
        var map: [Int: String] = [:]
        for song in songs {
            guard let id = song["id"] as? Int,
                  let album = song["album"] as? [String: Any],
                  let pic = album["picUrl"] as? String, !pic.isEmpty else { continue }
            map[id] = pic
        }
        return map
    }

    private func searchQQMusic(query: String) async throws -> [CatalogTrack] {
        var c = URLComponents(string: "https://c.y.qq.com/soso/fcgi-bin/client_search_cp")!
        c.queryItems = [URLQueryItem(name: "w", value: query), URLQueryItem(name: "format", value: "json"), URLQueryItem(name: "p", value: "1"), URLQueryItem(name: "n", value: "20")]
        let data = try await requestData(c.url!)
        return try Self.decodeQQTracks(data)
    }

    nonisolated static func decodeQQTracks(_ data: Data) throws -> [CatalogTrack] {
        let object: [String: Any]
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            object = json
        } else {
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = "MusicJsonCallback("
            let wrapper = text.hasSuffix(");") ? 2 : 1
            guard text.hasPrefix(prefix), text.hasSuffix(")") || text.hasSuffix(");"),
                  text.count >= prefix.count + wrapper,
                  let json = try JSONSerialization.jsonObject(with: Data(text.dropFirst(prefix.count).dropLast(wrapper).utf8)) as? [String: Any] else {
                throw URLError(.cannotParseResponse)
            }
            object = json
        }
        if let code = object["code"] as? Int, code != 0 { throw URLError(.badServerResponse) }
        let songs = (object["data"] as? [String: Any])?["song"] as? [String: Any]; let list = songs?["list"] as? [[String: Any]] ?? []
        return list.compactMap { song in
            guard let id = song["songmid"] as? String, let title = song["songname"] as? String, let singers = song["singer"] as? [[String: Any]], let artist = singers.first?["name"] as? String else { return nil }
            let artwork = (song["albummid"] as? String).flatMap { URL(string: "https://y.gtimg.cn/music/photo_new/T002R500x500M000\($0).jpg") }
            return CatalogTrack(id: "qq-\(id)", title: title, artist: artist, audioURL: URL(string: "https://example.invalid")!, license: .unknown, provider: "QQ音乐", artworkURL: artwork)
        }
    }

    private func searchKugou(query: String) async throws -> [CatalogTrack] {
        var c = URLComponents(string: "https://songsearch.kugou.com/song_search_v2")!
        c.queryItems = [
            URLQueryItem(name: "keyword", value: query),
            URLQueryItem(name: "pagesize", value: "20"),
            URLQueryItem(name: "page", value: "1")
        ]
        let object = try JSONSerialization.jsonObject(with: try await requestData(c.url!, timeout: 8)) as? [String: Any]
        let list = ((object?["data"] as? [String: Any])?["lists"] as? [[String: Any]]) ?? []
        return list.compactMap { song in
            guard let hash = song["FileHash"] as? String ?? song["HQFileHash"] as? String,
                  !hash.isEmpty,
                  let rawTitle = song["SongName"] as? String ?? song["FileName"] as? String else { return nil }
            let title = rawTitle.replacingOccurrences(of: "<em>", with: "").replacingOccurrences(of: "</em>", with: "")
            let rawArtist = song["SingerName"] as? String ?? "酷狗音乐"
            let artist = rawArtist.replacingOccurrences(of: "<em>", with: "").replacingOccurrences(of: "</em>", with: "")
            let artwork = (song["Image"] as? String)?.replacingOccurrences(of: "{size}", with: "400")
            return CatalogTrack(
                id: "kugou-\(hash)",
                title: title,
                artist: artist,
                audioURL: URL(string: "https://example.invalid")!,
                license: .unknown,
                provider: "酷狗音乐",
                artworkURL: artwork.flatMap(URL.init(string:))
            )
        }
    }

    func download(_ track: CatalogTrack, to directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard track.allowsDownload else { throw URLError(.userAuthenticationRequired) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(track.safeFilename)
        let (bytes, response) = try await session.bytes(for: URLRequest(url: track.audioURL))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        let expected = max(0, response.expectedContentLength)
        var data = Data()
        var lastReported = 0
        for try await byte in bytes {
            data.append(byte)
            if data.count - lastReported >= 64 * 1024 {
                try Task.checkCancellation()
                if expected > 0 { progress(min(Double(data.count) / Double(expected), 0.99)) }
                lastReported = data.count
            }
        }
        try Task.checkCancellation()
        guard !data.isEmpty else { throw URLError(.zeroByteResource) }
        try data.write(to: destination, options: .atomic); progress(1); return destination
    }

    func downloadArtwork(_ track: CatalogTrack, to directory: URL) async throws -> URL? {
        guard let url = track.artworkURL else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count <= 20 * 1024 * 1024,
              let image = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(image) > 0 else { throw URLError(.cannotDecodeContentData) }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("provider-artwork")
        try data.write(to: target, options: .atomic)
        return target
    }
}

private extension Array where Element == CatalogTrack {
    func removingDuplicates() -> [CatalogTrack] {
        var seen = Set<String>(); return filter { seen.insert($0.id).inserted }
    }
}

private extension Array where Element == String {
    func removingDuplicateStrings() -> [String] {
        var seen = Set<String>(); return filter { seen.insert($0).inserted }
    }
}
