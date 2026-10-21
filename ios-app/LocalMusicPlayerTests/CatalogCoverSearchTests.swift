import XCTest
import UIKit
@testable import LocalMusicPlayer

@MainActor
final class CatalogCoverSearchTests: XCTestCase {
    func testCoverMatchingIgnoresLiveVersionDurationAndRanksSameArtistFirst() throws {
        let query = MusicResourceQuery(title: "明天你好 (Live)", artist: "薛之谦,合唱者", album: "现场", duration: 999)
        let original = try XCTUnwrap(CoverQueryPolicy.score(title: "明天，你好", artist: "牛奶咖啡", album: "早上好", query: query, fallback: false))
        let sameArtist = try XCTUnwrap(CoverQueryPolicy.score(title: "明天你好", artist: "薛之谦", album: "", query: query, fallback: false))
        XCTAssertGreaterThan(sameArtist, original)
        XCTAssertNil(CoverQueryPolicy.score(title: "完全无关", artist: "其他人", album: "", query: query, fallback: false))
    }

    func testChineseImportsQueryDomesticSourcesFirstAndNeverBaidu() async throws {
        let fixture = CoverHTTPFixtures(image: imageData())
        let service = CatalogCoverSearch(transport: fixture)
        let result = try await service.findCover(MusicResourceQuery(title: "无匹配中文歌", artist: "", album: "", duration: 0))
        XCTAssertNil(result)
        let requests = await fixture.requests
        XCTAssertEqual(Set(requests.prefix(3).compactMap { $0.url?.host }), ["music.163.com", "c.y.qq.com", "mobilecdn.kugou.com"])
        XCTAssertEqual(Set(requests.compactMap { $0.url?.host }), ["music.163.com", "c.y.qq.com", "mobilecdn.kugou.com", "itunes.apple.com", "musicbrainz.org", "api.jamendo.com", "archive.org"])
        XCTAssertFalse(requests.contains { $0.url?.host == "qianfan.baidubce.com" })
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
    }

    func testEnglishImportsQueryForeignSourcesFirstAndStillCrossFallback() async throws {
        let fixture = CoverHTTPFixtures(image: imageData())
        let service = CatalogCoverSearch(transport: fixture)
        _ = try await service.findCover(MusicResourceQuery(title: "Unknown English Song", artist: "周深", album: "", duration: 0))
        let requests = await fixture.requests
        XCTAssertEqual(Set(requests.prefix(3).compactMap { $0.url?.host }), ["itunes.apple.com", "musicbrainz.org", "api.jamendo.com"])
        XCTAssertTrue(requests.contains { $0.url?.host == "music.163.com" })
        let archiveIndex = try XCTUnwrap(requests.firstIndex { $0.url?.host == "archive.org" })
        let domesticIndex = try XCTUnwrap(requests.firstIndex { $0.url?.host == "music.163.com" })
        XCTAssertLessThan(archiveIndex, domesticIndex)
    }

    func testNetEaseSearchWithOnlyPicIDLoadsSongDetailThenDownloadsRealCover() async throws {
        let fixture = CoverHTTPFixtures(mode: .neteaseDetail, image: imageData())
        let service = CatalogCoverSearch(transport: fixture, providers: [.netease])
        let result = try await service.findCover(MusicResourceQuery(title: "明天你好 (Live)", artist: "", album: "", duration: 999))
        XCTAssertEqual(result?.provider, "netease")
        XCTAssertNotNil(result.flatMap { UIImage(data: $0.data) })
        let requests = await fixture.requests
        XCTAssertEqual(requests.map { $0.url?.path ?? "" }, ["/api/search/get", "/api/song/detail/", "/cover.png"])
        let queryItems = URLComponents(url: try XCTUnwrap(requests.first?.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(queryItems?.first(where: { $0.name == "s" })?.value, "明天你好")
    }

    func testFailedDomesticSourceCannotHideAnotherSourceCover() async throws {
        let fixture = CoverHTTPFixtures(mode: .failedNetEase, image: imageData())
        let service = CatalogCoverSearch(transport: fixture, providers: [.netease, .itunes])
        let result = try await service.findCover(MusicResourceQuery(title: "明天你好 (Cover 牛奶咖啡)", artist: "歌手", album: "", duration: 600))
        XCTAssertEqual(result?.provider, "itunes")
        XCTAssertFalse(result?.artistFallback ?? true)
        XCTAssertNotNil(result.flatMap { UIImage(data: $0.data) })
    }

    func testLaterDetailFailureKeepsEarlierUsableCandidate() async throws {
        let fixture = CoverHTTPFixtures(mode: .laterDetailFailure, image: imageData())
        let service = CatalogCoverSearch(transport: fixture, providers: [.netease])
        let result = try await service.findCover(MusicResourceQuery(title: "明天你好", artist: "", album: "", duration: 0))
        XCTAssertEqual(result?.provider, "netease")
        XCTAssertNotNil(result.flatMap { UIImage(data: $0.data) })
    }

    func testTargetAlbumIsRankedBeforeTruncatingSongDetails() async throws {
        let fixture = CoverHTTPFixtures(mode: .albumRanking, image: imageData())
        let service = CatalogCoverSearch(transport: fixture, providers: [.netease])
        let result = try await service.findCover(MusicResourceQuery(title: "明天你好", artist: "牛奶咖啡", album: "目标专辑", duration: 0))
        XCTAssertEqual(result?.imageURL.lastPathComponent, "target.png")
    }

    func testArtistAlbumIsUsedOnlyAfterSongSearchHasNoResult() async throws {
        let fixture = CoverHTTPFixtures(mode: .artistFallback, image: imageData())
        let service = CatalogCoverSearch(transport: fixture, providers: [.itunes])
        let result = try await service.findCover(MusicResourceQuery(title: "找不到的录音", artist: "王杰", album: "", duration: 0))
        XCTAssertEqual(result?.artistFallback, true)
        XCTAssertEqual(result?.title, "一场游戏一场梦")
        let requests = await fixture.requests
        let terms = requests.filter { $0.url?.host == "itunes.apple.com" }.compactMap {
            URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "term" })?.value
        }
        XCTAssertEqual(terms, ["找不到的录音", "王杰"])
    }

    func testOtherProvidersParseTheirOwnCoverResponses() async throws {
        for provider in [CoverProvider.qq, .kugou, .musicbrainz, .jamendo, .archive] {
            let fixture = CoverHTTPFixtures(mode: .otherProviders, image: imageData())
            let service = CatalogCoverSearch(transport: fixture, providers: [provider])
            let result = try await service.findCover(MusicResourceQuery(title: "Example Song", artist: "Artist", album: "Album", duration: 999))
            XCTAssertEqual(result?.provider, provider.rawValue, "\(provider) 必须解析自身响应中的封面")
            XCTAssertNotNil(result.flatMap { UIImage(data: $0.data) })
        }
    }

    func testSlowLookupIsCancelledWithinOverallBudget() async throws {
        let fixture = CoverHTTPFixtures(mode: .slow, image: imageData())
        let service = CatalogCoverSearch(transport: fixture, providers: [.itunes], searchWindow: 0.01)
        let started = Date()
        let result = try await service.findCover(MusicResourceQuery(title: "Example Song", artist: "", album: "", duration: 0))
        XCTAssertNil(result)
        XCTAssertLessThan(Date().timeIntervalSince(started), 8, "不能无限等待持续不返回的来源")
    }

    func testMusicBrainzRanksAllReleaseAlbumsBeforeLimitingImageDownloads() async throws {
        let fixture = CoverHTTPFixtures(mode: .musicBrainzAlbums, image: imageData())
        let service = CatalogCoverSearch(transport: fixture, providers: [.musicbrainz])
        let result = try await service.findCover(MusicResourceQuery(title: "Example Song", artist: "Artist", album: "Target Album", duration: 0))
        XCTAssertTrue(result?.imageURL.path.contains("12345678-1234-1234-1234-123456789003") ?? false)
    }

    private func imageData() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 240))
        }.pngData()!
    }
}

private actor CoverHTTPFixtures: CoverHTTPTransport {
    enum Mode: Sendable { case empty, neteaseDetail, failedNetEase, artistFallback, laterDetailFailure, albumRanking, otherProviders, slow, musicBrainzAlbums }
    let mode: Mode
    let image: Data
    private(set) var requests: [URLRequest] = []
    init(mode: Mode = .empty, image: Data) { self.mode = mode; self.image = image }
    func data(for request: URLRequest, limit: Int) async throws -> Data {
        requests.append(request)
        let url = request.url!
        if url.host == "example.org" { return image }
        if mode == .slow { try await Task.sleep(for: .seconds(60)); return Data() }
        if mode == .musicBrainzAlbums {
            if url.host == "coverartarchive.org" { return image }
            return Data(#"{"recordings":[{"title":"Example Song","artist-credit":[{"name":"Artist"}],"releases":[{"id":"12345678-1234-1234-1234-123456789001","title":"Other Album 1"},{"id":"12345678-1234-1234-1234-123456789002","title":"Other Album 2"},{"id":"12345678-1234-1234-1234-123456789003","title":"Target Album"}]}]}"#.utf8)
        }
        if mode == .otherProviders {
            switch url.host {
            case "c.y.qq.com": return Data(#"{"data":{"song":{"list":[{"songname":"Example Song","singer":[{"name":"Artist"}],"albumname":"Album","albummid":"abc123"}]}}}"#.utf8)
            case "y.gtimg.cn", "imge.kugou.com", "coverartarchive.org": return image
            case "mobilecdn.kugou.com":
                if url.path == "/api/v3/album/info" { return Data(#"{"data":{"albumname":"Album","imgurl":"http://imge.kugou.com/stdmusic/{size}/cover.jpg"}}"#.utf8) }
                return Data(#"{"data":{"info":[{"songname":"Example Song","singername":"Artist","album_id":42}]}}"#.utf8)
            case "musicbrainz.org": return Data(#"{"recordings":[{"title":"Example Song","artist-credit":[{"name":"Artist"}],"releases":[{"id":"12345678-1234-1234-1234-123456789012","title":"Album"}]}]}"#.utf8)
            case "api.jamendo.com": return Data(#"{"headers":{"status":"success"},"results":[{"name":"Example Song","artist_name":"Artist","album_name":"Album","image":"https://example.org/cover.png"}]}"#.utf8)
            case "archive.org":
                if url.path.hasPrefix("/download/") { return image }
                if url.path.hasPrefix("/metadata/") { return Data(#"{"files":[{"name":"cover.jpg","format":"JPEG"}]}"#.utf8) }
                return Data(#"{"response":{"docs":[{"identifier":"album-123","title":"Example Song","creator":["Artist"]}]}}"#.utf8)
            default: break
            }
        }
        if mode == .neteaseDetail {
            if url.path == "/api/search/get" { return Data(#"{"code":200,"result":{"songs":[{"id":123,"name":"明天你好","artists":[{"name":"牛奶咖啡"}],"album":{"name":"早上好","picId":999}}]}}"#.utf8) }
            if url.path == "/api/song/detail/" { return Data(#"{"code":200,"songs":[{"album":{"name":"早上好","picUrl":"https://example.org/cover.png"}}]}"#.utf8) }
        }
        if mode == .laterDetailFailure {
            if url.path == "/api/search/get" { return Data(#"{"code":200,"result":{"songs":[{"id":123,"name":"明天你好","artists":[{"name":"牛奶咖啡"}],"album":{}},{"id":456,"name":"明天你好","artists":[{"name":"其他人"}],"album":{}}]}}"#.utf8) }
            if url.path == "/api/song/detail/" {
                let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value
                if id == "456" { throw URLError(.timedOut) }
                return Data(#"{"songs":[{"album":{"name":"早上好","picUrl":"https://example.org/cover.png"}}]}"#.utf8)
            }
        }
        if mode == .albumRanking, url.path == "/api/search/get" {
            return Data(#"{"code":200,"result":{"songs":[{"id":1,"name":"明天你好","artists":[{"name":"牛奶咖啡"}],"album":{"name":"其他专辑1","picUrl":"https://example.org/other1.png"}},{"id":2,"name":"明天你好","artists":[{"name":"牛奶咖啡"}],"album":{"name":"其他专辑2","picUrl":"https://example.org/other2.png"}},{"id":3,"name":"明天你好","artists":[{"name":"牛奶咖啡"}],"album":{"name":"目标专辑","picUrl":"https://example.org/target.png"}}]}}"#.utf8)
        }
        if mode == .failedNetEase {
            if url.host == "music.163.com" { throw URLError(.cannotConnectToHost) }
            if url.host == "itunes.apple.com" { return Data(#"{"results":[{"trackName":"明天，你好","artistName":"牛奶咖啡","collectionName":"早上好","artworkUrl100":"https://example.org/cover.png"}]}"#.utf8) }
        }
        if mode == .artistFallback, url.host == "itunes.apple.com" {
            let term = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "term" })?.value
            if term == "王杰" { return Data(#"{"results":[{"collectionName":"一场游戏一场梦","artistName":"王杰","artworkUrl100":"https://example.org/cover.png"}]}"#.utf8) }
        }
        // 每个服务都返回自身真实使用的外层结构，不能用同一空对象掩盖解析错误。
        switch url.host {
        case "music.163.com": return Data(#"{"code":200,"result":{"songs":[]}}"#.utf8)
        case "c.y.qq.com": return Data(#"{"data":{"song":{"list":[]}}}"#.utf8)
        case "mobilecdn.kugou.com": return Data(#"{"data":{"info":[]}}"#.utf8)
        case "musicbrainz.org": return Data(#"{"recordings":[]}"#.utf8)
        case "archive.org": return Data(#"{"response":{"docs":[]}}"#.utf8)
        default: return Data(#"{"results":[]}"#.utf8)
        }
    }
}
