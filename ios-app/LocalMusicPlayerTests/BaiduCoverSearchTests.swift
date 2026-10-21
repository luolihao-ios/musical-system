import XCTest
import UIKit
@testable import LocalMusicPlayer

@MainActor
final class BaiduCoverSearchTests: XCTestCase {
    func testOfficialImageRequestAndDownloadKeepAPIKeyOffImageHost() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 240, height: 240))
        }.pngData()!
        let response = Data(#"{"references":[{"title":"明天你好 专辑封面","url":"https://example.org/album","image":{"url":"https://example.org/cover.png","width":"240","height":"240"}}]}"#.utf8)
        let transport = CoverFixtureTransport(replies: [response, image])
        let service = BaiduCoverSearch(transport: transport, apiKey: { "fixture-key" })
        let match = try await service.findCover(MusicResourceQuery(title: "明天你好 (Live)", artist: "", album: "", duration: 999))
        XCTAssertNotNil(match)
        XCTAssertNotNil(match.flatMap { UIImage(data: $0.data) })
        XCTAssertEqual(match?.pageURL?.absoluteString, "https://example.org/album")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://qianfan.baidubce.com/v2/ai_search/web_search")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requests[0].httpBody)) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages.first?["content"], "明天你好 歌曲 封面")
        let types = try XCTUnwrap(body["resource_type_filter"] as? [[String: Any]])
        XCTAssertEqual(types.first?["type"] as? String, "image")
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Authorization"))
    }

    func testSongSearchRemovesVersionSuffixWithoutRequiringDuration() {
        let query = MusicResourceQuery(title: "明天你好 (Live)", artist: "薛之谦", album: "", duration: 900)
        XCTAssertEqual(BaiduCoverSearch.searchTerms(for: query), ["明天你好 歌曲 封面", "薛之谦 专辑 封面"])
    }

    func testImageResultsPreferSameArtistButAllowOtherVersions() throws {
        let data = Data(#"{"references":[{"title":"明天你好 牛奶咖啡 封面","url":"https://example.org/a","type":"image","image":{"url":"https://example.org/a.jpg","width":"600","height":"600"}},{"title":"明天你好 薛之谦 Live 封面","url":"https://example.org/b","type":"image","image":{"url":"https://example.org/b.jpg","width":"600","height":"600"}},{"title":"完全无关的广告","url":"https://example.org/c","type":"image","image":{"url":"https://example.org/c.jpg","width":"600","height":"600"}}]}"#.utf8)
        let query = MusicResourceQuery(title: "明天你好", artist: "薛之谦", album: "", duration: 1)
        let candidates = try BaiduCoverSearch.candidates(from: data, query: query, artistFallback: false)
        XCTAssertEqual(candidates.map(\.imageURL.lastPathComponent), ["b.jpg", "a.jpg"])
    }

    func testArtistFallbackAcceptsAlbumAndRejectsUnrelatedResult() throws {
        let data = Data(#"{"references":[{"title":"王杰 一场游戏一场梦 专辑封面","url":"https://example.org/a","image":{"url":"https://example.org/a.jpg"}},{"title":"其他歌手 专辑","url":"https://example.org/b","image":{"url":"https://example.org/b.jpg"}}]}"#.utf8)
        let query = MusicResourceQuery(title: "无法找到的现场录音", artist: "王杰", album: "", duration: 0)
        XCTAssertEqual(try BaiduCoverSearch.candidates(from: data, query: query, artistFallback: true).count, 1)
    }

    func testMissingKeyDoesNotCallNetwork() async {
        let transport = ForbiddenCoverTransport()
        let service = BaiduCoverSearch(transport: transport, apiKey: { nil })
        do {
            _ = try await service.findCover(MusicResourceQuery(title: "你好", artist: "", album: "", duration: 0))
            XCTFail("没有密钥时应明确报告未配置")
        } catch { XCTAssertEqual(error as? CoverSearchError, .notConfigured) }
        let count = await transport.calls
        XCTAssertEqual(count, 0)
    }

    func testGeneratedArtworkRemainsEligibleButEmbeddedArtworkDoesNot() {
        XCTAssertTrue(CoverArtworkPolicy.needsSearch(path: "/music/artwork-generated.jpg"))
        XCTAssertTrue(CoverArtworkPolicy.needsSearch(path: nil))
        XCTAssertFalse(CoverArtworkPolicy.needsSearch(path: "/music/artwork"))
        XCTAssertFalse(CoverArtworkPolicy.needsSearch(path: "/music/artwork-baidu.jpg"))
    }

    func testSystemLibraryGeneratedCoverIsEligibleWithoutReplacingCustomImages() {
        XCTAssertTrue(CoverArtworkPolicy.needsSearch(path: "/support/SystemArtwork/media-123-generated.jpg"))
        XCTAssertFalse(CoverArtworkPolicy.needsSearch(path: "/support/SystemArtwork/media-123.jpg"))
        XCTAssertFalse(CoverArtworkPolicy.needsSearch(path: "/music/my-generated.jpg"))
    }
}

private actor CoverFixtureTransport: CoverHTTPTransport {
    private var replies: [Data]
    private(set) var requests: [URLRequest] = []
    init(replies: [Data]) { self.replies = replies }
    func data(for request: URLRequest, limit: Int) async throws -> Data {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.resourceUnavailable) }
        return replies.removeFirst()
    }
}

private actor ForbiddenCoverTransport: CoverHTTPTransport {
    private(set) var calls = 0
    func data(for request: URLRequest, limit: Int) async throws -> Data {
        calls += 1
        throw URLError(.unsupportedURL)
    }
}
