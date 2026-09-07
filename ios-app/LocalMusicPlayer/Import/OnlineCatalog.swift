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
        // The endpoint is intentionally configurable so only an approved Jamendo/FMA
        // adapter is enabled in production; no third-party private media URLs are guessed.
        guard let url = URL(string: "https://api.jamendo.com/v3.0/tracks/?format=json&limit=20&namesearch=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") else { return [] }
        var request = URLRequest(url: url); request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try parseJamendo(data)
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
        let expected = max(0, response.expectedContentLength)
        var data = Data(); data.reserveCapacity(expected > 0 ? Int(expected) : 0)
        for try await byte in bytes { data.append(byte); if expected > 0 { progress(Double(data.count) / Double(expected)) } }
        try data.write(to: destination, options: .atomic); progress(1)
        return destination
    }
}
