import Foundation
import UIKit

struct MusicResourceQuery: Sendable {
    let title: String
    let artist: String
    let album: String
    let duration: Double
}
struct MusicResourceResult: Sendable { var lyrics: String?; var cover: Data? }
protocol MusicResourceSearching: Sendable {
    func search(_ query: MusicResourceQuery, lyrics: Bool, cover: Bool) async -> MusicResourceResult
}

actor OnlineMusicResources: MusicResourceSearching {
    static let shared = OnlineMusicResources()
    private var lastRequest = Date.distantPast
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }
    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }
    static func matches(_ query: MusicResourceQuery, title: String, artist: String, duration: Double?) -> Bool {
        guard normalized(title) == normalized(query.title) else { return false }
        if query.artist.isEmpty { guard query.duration > 0, duration != nil else { return false } }
        else if normalized(artist) != normalized(query.artist) { return false }
        if query.duration > 0, let duration { return abs(query.duration - duration) <= 3 }
        return true
    }
    func search(_ query: MusicResourceQuery, lyrics: Bool, cover: Bool) async -> MusicResourceResult {
        var result = MusicResourceResult()
        guard !query.title.isEmpty else { return result }
        log("Lookup started: title=\(query.title); artist=\(query.artist); lyrics=\(lyrics); cover=\(cover)")
        if lyrics {
            do {
                var parameters = ["track_name": query.title]
                if !query.artist.isEmpty { parameters["artist_name"] = query.artist }
                let data = try await get("https://lrclib.net/api/search", parameters)
                let candidates = try JSONDecoder().decode([LyricCandidate].self, from: data)
                let matches = candidates.filter { Self.matches(query, title: $0.trackName, artist: $0.artistName, duration: $0.duration) }
                if (query.artist.isEmpty ? Set(matches.map { Self.normalized($0.artistName) }).count == 1 : true), let match = matches.first {
                    result.lyrics = match.syncedLyrics?.isEmpty == false ? match.syncedLyrics : match.plainLyrics
                }
                log("Lyrics lookup finished; found=\(result.lyrics != nil)")
            } catch { log("Lyrics lookup unavailable: \(error.localizedDescription)") }
        }
        if cover {
            do {
                let phrase: (String) -> String = { $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
                let expression = "recording:\"\(phrase(query.title))\"" + (query.artist.isEmpty ? "" : " AND artist:\"\(phrase(query.artist))\"")
                let data = try await get("https://musicbrainz.org/ws/2/recording", ["query": expression, "fmt": "json", "limit": "10"])
                let response = try JSONDecoder().decode(RecordingResponse.self, from: data)
                let matches = response.recordings.filter { record in
                    Self.matches(query, title: record.title, artist: record.credits.map(\.name).joined(), duration: record.length.map { Double($0) / 1000 })
                }
                let unambiguous = !query.artist.isEmpty || Set(matches.map { Self.normalized($0.credits.map(\.name).joined()) }).count == 1
                let releases = unambiguous ? (matches.first?.releases ?? []) : []
                let release = query.album.isEmpty ? releases.first : releases.first { Self.normalized($0.title) == Self.normalized(query.album) }
                if let release, UUID(uuidString: release.id) != nil {
                    let bytes = try await get("https://coverartarchive.org/release/\(release.id)/front-500", [:], maxBytes: 5 * 1024 * 1024)
                    if UIImage(data: bytes) != nil { result.cover = bytes }
                }
                log("Cover lookup finished; found=\(result.cover != nil)")
            } catch { log("Cover lookup unavailable: \(error.localizedDescription)") }
        }
        return result
    }
    private func get(_ endpoint: String, _ query: [String: String], maxBytes: Int = 2 * 1024 * 1024) async throws -> Data {
        // Schedule slots before suspending: actor reentrancy must not burst requests.
        let date = max(Date(), lastRequest.addingTimeInterval(1.1)); lastRequest = date
        let delay = date.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        var parts = URLComponents(string: endpoint)!
        if !query.isEmpty { parts.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: parts.url!); request.timeoutInterval = 12
        request.setValue("AiYueCity/1.0 (https://github.com/luolihao-ios/musical-system)", forHTTPHeaderField: "User-Agent")
        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, response.expectedContentLength <= maxBytes else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in stream { guard data.count < maxBytes else { throw URLError(.dataLengthExceedsMaximum) }; data.append(byte) }
        return data
    }
    private func log(_ text: String) {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = documents.appendingPathComponent("music-import-diagnostics.log")
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }; defer { try? handle.close() }
        try? handle.seekToEnd(); try? handle.write(contentsOf: Data("\(Date()) \(text)\n".utf8))
    }
    private struct LyricCandidate: Decodable { let trackName, artistName: String; let duration: Double; let syncedLyrics, plainLyrics: String? }
    private struct RecordingResponse: Decodable { let recordings: [Recording] }
    private struct Recording: Decodable {
        let title: String; let length: Int?; let credits: [Credit]; let releases: [Release]?
        enum CodingKeys: String, CodingKey { case title, length, releases; case credits = "artist-credit" }
    }
    private struct Credit: Decodable { let name: String }
    private struct Release: Decodable { let id, title: String }
}
