import Foundation

enum CoverSearchError: Error, Equatable, LocalizedError {
    case authentication, quota, invalidResponse
    var errorDescription: String? {
        switch self {
        case .authentication: "搜索来源鉴权失败或服务尚未开通"
        case .quota: "搜索来源额度不足，请稍后再试"
        case .invalidResponse: "搜索来源返回无效数据或暂时不可用"
        }
    }
}

struct CoverArtMatch: Sendable {
    let data: Data
    let imageURL: URL
    let pageURL: URL?
    let title: String
    let artistFallback: Bool
    let provider: String

    init(data: Data, imageURL: URL, pageURL: URL?, title: String, artistFallback: Bool, provider: String) {
        self.data = data; self.imageURL = imageURL; self.pageURL = pageURL
        self.title = title; self.artistFallback = artistFallback; self.provider = provider
    }
}

protocol CoverArtSearching: Sendable {
    func isAvailable() async -> Bool
    func findCover(_ query: MusicResourceQuery) async throws -> CoverArtMatch?
}

enum CoverArtworkPolicy {
    static func needsSearch(path: String?) -> Bool {
        guard let path else { return true }
        let url = URL(fileURLWithPath: path)
        return url.lastPathComponent == "artwork-generated.jpg"
            || (url.deletingLastPathComponent().lastPathComponent == "SystemArtwork"
                && url.lastPathComponent.hasSuffix("-generated.jpg"))
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
        CoverSearchDiagnostics.log("HTTP host=\(request.url?.host ?? "?") path=\(request.url?.path ?? "?") status=\(http.statusCode)")
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
