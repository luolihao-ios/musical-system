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
        var results = try await searchInternetArchive(query: query)
        // Jamendo 官方文档提供的只读测试 ID，用于测试构建；正式发布前替换为开发者应用 ID。
        let clientID = UserDefaults.standard.string(forKey: "jamendoClientID") ?? "709fa152"
        if !clientID.isEmpty { results.append(contentsOf: try await searchJamendo(query: query, clientID: clientID)) }
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
            URLQueryItem(name: "q", value: "mediatype:audio AND (title:\(query) OR creator:\(query))"),
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
            return CatalogTrack(id: String(item.id), title: item.name, artist: item.artist_name, audioURL: url, license: license)
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
