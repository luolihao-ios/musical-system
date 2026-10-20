import Foundation
import ImageIO
import Security
import UIKit

enum CoverSearchError: Error, Equatable, LocalizedError {
    case notConfigured, authentication, quota, invalidResponse
    var errorDescription: String? {
        switch self {
        case .notConfigured: "请先在设置中配置百度搜索 API Key"
        case .authentication: "百度搜索密钥无效或尚未开通服务"
        case .quota: "百度搜索额度不足，请稍后再试"
        case .invalidResponse: "百度搜索暂时不可用"
        }
    }
}

struct CoverArtMatch: Sendable {
    let data: Data
    let imageURL: URL
    let pageURL: URL?
    let title: String
    let artistFallback: Bool
}

protocol CoverArtSearching: Sendable {
    func isAvailable() async -> Bool
    func findCover(_ query: MusicResourceQuery) async throws -> CoverArtMatch?
}

enum CoverArtworkPolicy {
    static func needsSearch(path: String?) -> Bool {
        guard let path else { return true }
        return URL(fileURLWithPath: path).lastPathComponent == "artwork-generated.jpg"
    }
}

// 试用密钥由用户在手机中配置；不写入仓库、IPA 或诊断日志。
enum BaiduSearchCredentials {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.luolihao.musicalsystem.baidu-search",
         kSecAttrAccount as String: "api-key"]
    }
    static func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { SecItemDelete(query as CFDictionary); return }
        let data = Data(trimmed.utf8)
        let result = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw CoverSearchError.notConfigured }
        } else if result != errSecSuccess { throw CoverSearchError.notConfigured }
    }
}

protocol CoverHTTPTransport: Sendable {
    func data(for request: URLRequest, limit: Int) async throws -> Data
}

struct LimitedCoverHTTPTransport: CoverHTTPTransport {
    let session: URLSession = .shared
    func data(for request: URLRequest, limit: Int) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw CoverSearchError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw CoverSearchError.authentication }
        if http.statusCode == 429 { throw CoverSearchError.quota }
        guard (200..<300).contains(http.statusCode), response.expectedContentLength <= limit else {
            throw CoverSearchError.invalidResponse
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }
}

actor BaiduCoverSearch: CoverArtSearching {
    static let shared = BaiduCoverSearch()
    private let transport: any CoverHTTPTransport
    private let apiKey: @Sendable () -> String?
    private var nextSearch = Date.distantPast

    init(transport: any CoverHTTPTransport = LimitedCoverHTTPTransport(),
         apiKey: @escaping @Sendable () -> String? = { BaiduSearchCredentials.read() }) {
        self.transport = transport
        self.apiKey = apiKey
    }

    func isAvailable() -> Bool { !(apiKey()?.isEmpty ?? true) }

    static func cleanedTitle(_ title: String) -> String {
        title.replacingOccurrences(
            of: #"[\(（\[【][^\)）\]】]*(?:live|cover|现场|翻唱|伴奏|remix)[^\)）\]】]*[\)）\]】]"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func searchTerms(for query: MusicResourceQuery) -> [String] {
        var terms: [String] = []
        let title = cleanedTitle(query.title)
        if !title.isEmpty { terms.append("\(title) 歌曲 封面") }
        let artist = query.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if !artist.isEmpty { terms.append("\(artist) 专辑 封面") }
        return terms
    }

    struct Candidate: Sendable {
        let title: String
        let imageURL: URL
        let pageURL: URL?
        let score: Int
    }

    // 只解析百度官方图片搜索结果，不读取百度网页内部接口。
    static func candidates(from data: Data, query: MusicResourceQuery, artistFallback: Bool) throws -> [Candidate] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let references = root["references"] as? [[String: Any]] else { throw CoverSearchError.invalidResponse }
        let title = OnlineMusicResources.normalized(cleanedTitle(query.title))
        let artist = OnlineMusicResources.normalized(query.artist)
        var seen = Set<URL>()
        var candidates: [Candidate] = []
        for (index, reference) in references.enumerated() {
            let label = reference["title"] as? String ?? ""
            let text = OnlineMusicResources.normalized(label + " " + (reference["content"] as? String ?? ""))
            let required = artistFallback ? artist : title
            guard !required.isEmpty, text.contains(required) else { continue }
            var images: [[String: Any]] = []
            if let image = reference["image"] as? [String: Any] { images.append(image) }
            if let extensions = reference["web_extensions"] as? [String: Any],
               let related = extensions["images"] as? [[String: Any]] { images += related }
            for image in images {
                guard let raw = image["url"] as? String, let url = URL(string: raw), url.scheme == "https",
                      seen.insert(url).inserted else { continue }
                let width = Double("\(image["width"] ?? "0")") ?? 0
                let height = Double("\(image["height"] ?? "0")") ?? 0
                if width > 0, height > 0, (min(width, height) < 120 || width / height < 0.65 || width / height > 1.55) { continue }
                let sameArtist = !artist.isEmpty && text.contains(artist)
                let album = OnlineMusicResources.normalized(query.album)
                let sameAlbum = !album.isEmpty && text.contains(album)
                let score = (sameArtist ? 100 : 0) + (sameAlbum ? 40 : 0) + (text.contains("封面") ? 10 : 0) - index
                candidates.append(Candidate(title: label, imageURL: url,
                    pageURL: (reference["url"] as? String).flatMap(URL.init(string:)), score: score))
            }
        }
        return candidates.sorted { $0.score > $1.score }
    }

    func findCover(_ query: MusicResourceQuery) async throws -> CoverArtMatch? {
        guard let key = apiKey(), !key.isEmpty else { throw CoverSearchError.notConfigured }
        return try await withThrowingTaskGroup(of: CoverArtMatch?.self) { group in
            group.addTask { try await self.search(query, key: key) }
            group.addTask {
                try await Task.sleep(for: .seconds(14))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            return try await group.next() ?? nil
        }
    }

    private func search(_ query: MusicResourceQuery, key: String) async throws -> CoverArtMatch? {
        // 总预算包含节流、关键词查询和图片下载；每首最多两轮查询。
        let deadline = Date().addingTimeInterval(14)
        let terms = Self.searchTerms(for: query)
        for term in terms {
            try Task.checkCancellation()
            let slot = max(Date(), nextSearch)
            nextSearch = slot.addingTimeInterval(1.1)
            let delay = slot.timeIntervalSinceNow
            guard delay < deadline.timeIntervalSinceNow else { break }
            if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
            guard deadline.timeIntervalSinceNow > 1 else { break }
            let artistFallback = term == "\(query.artist.trimmingCharacters(in: .whitespacesAndNewlines)) 专辑 封面"
            var request = URLRequest(url: URL(string: "https://qianfan.baidubce.com/v2/ai_search/web_search")!)
            request.httpMethod = "POST"
            request.timeoutInterval = min(5, deadline.timeIntervalSinceNow)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "messages": [["role": "user", "content": term]], "edition": "lite",
                "search_source": "baidu_search_v2",
                "resource_type_filter": [["type": "image", "top_k": 8], ["type": "web", "top_k": 0], ["type": "video", "top_k": 0], ["type": "aladdin", "top_k": 0]]
            ])
            let started = Date()
            let data: Data
            do { data = try await transport.data(for: request, limit: 2_000_000) }
            catch let error as CoverSearchError { throw error }
            catch { continue }
            let candidates = try Self.candidates(from: data, query: query, artistFallback: artistFallback)
            PlayerInteractionDiagnostics.log("cover baidu stage=\(artistFallback ? "artist-album" : "song") candidates=\(candidates.count) seconds=\(Date().timeIntervalSince(started))")
            for candidate in candidates.prefix(2) {
                try Task.checkCancellation()
                guard deadline.timeIntervalSinceNow > 1 else { break }
                var imageRequest = URLRequest(url: candidate.imageURL)
                imageRequest.timeoutInterval = min(4, deadline.timeIntervalSinceNow)
                // 图片下载不携带百度 API Key。
                guard let bytes = try? await transport.data(for: imageRequest, limit: 4_000_000),
                      let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 800,
                        kCGImageSourceCreateThumbnailWithTransform: true
                      ] as CFDictionary), min(image.width, image.height) >= 120,
                      Double(image.width) / Double(image.height) >= 0.65,
                      Double(image.width) / Double(image.height) <= 1.55,
                      let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.88) else { continue }
                return CoverArtMatch(data: jpeg, imageURL: candidate.imageURL, pageURL: candidate.pageURL,
                                     title: candidate.title, artistFallback: artistFallback)
            }
        }
        return nil
    }
}
