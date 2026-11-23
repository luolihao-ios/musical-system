import XCTest
@testable import LocalMusicPlayer

final class OnlineCatalogTests: XCTestCase {
    func testQQOrdinaryJSONAndJSONPKeepTheSameSong() throws {
        let json = #"{"data":{"song":{"list":[{"songmid":"qq-id","songname":"晴天","singer":[{"name":"周杰伦"}]}]}}}"#
        for payload in [json, "MusicJsonCallback(" + json + ");\n"] {
            let songs = try OnlineCatalog.decodeQQTracks(Data(payload.utf8))
            XCTAssertEqual(songs.map(\.id), ["qq-qq-id"])
            XCTAssertEqual(songs.first?.title, "晴天")
        }
    }

    func testUSStorefrontWinsOverChineseDeviceRegion() {
        XCTAssertEqual(OnlineCatalog.iTunesRegion(storefront: "USA", locale: Locale(identifier: "zh_CN")), "US")
        XCTAssertEqual(OnlineCatalog.iTunesRegion(storefront: nil, locale: Locale(identifier: "zh_CN")), "CN")
    }

    func testITunesCatalogRowsNeverExposeAppleAudioForPlaybackOrDownload() throws {
        let json = #"{"resultCount":1,"results":[{"kind":"song","trackId":42,"trackName":"Anti-Hero","artistName":"Taylor Swift","artworkUrl100":"https://example.org/cover.jpg","previewUrl":"https://example.org/audio.m4a"}]}"#
        let tracks = try OnlineCatalog.decodeITunesTracks(Data(json.utf8), region: "US")
        let row = try XCTUnwrap(tracks.first)
        XCTAssertEqual(row.title, "Anti-Hero")
        XCTAssertEqual(row.provider, "iTunes · US")
        XCTAssertNil(row.previewURL)
        XCTAssertNil(row.artworkURL)
        XCTAssertFalse(row.allowsDownload)
    }

    func testITunesZeroDoesNotHideTheQQSearchResult() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SearchFallbackProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let catalog = OnlineCatalog(session: session, iTunesStorefront: { "CHN" })
        let tracks = try await catalog.search(query: "晴天")
        XCTAssertEqual(tracks.map(\.id), ["qq-qq-id"])
        XCTAssertEqual(tracks.first?.title, "晴天")
    }
    func testJamendoStringIDsAndArtistDownloadPermission() async throws {
        let data = Data(#"{"results":[{"id":"7","name":"A","artist_name":"Artist","audio":"https://example.org/stream.mp3","audiodownload":"https://example.org/download.mp3","audiodownload_allowed":false,"license_ccurl":"https://creativecommons.org/licenses/by/4.0/"},{"id":"8","name":"B","artist_name":"Artist","audio":"https://example.org/stream.mp3","audiodownload":"https://example.org/download.mp3","audiodownload_allowed":true,"license_ccurl":"https://creativecommons.org/licenses/by/4.0/"}]}"#.utf8)
        let tracks = try await OnlineCatalog().parseJamendo(data)
        XCTAssertEqual(tracks.map(\.id), ["jamendo-7", "jamendo-8"])
        XCTAssertEqual(tracks.map(\.allowsDownload), [false, true])
        XCTAssertEqual(tracks.last?.audioURL.absoluteString, "https://example.org/download.mp3")
        XCTAssertEqual(tracks.last?.previewURL?.absoluteString, "https://example.org/stream.mp3")
    }
    func testJamendoArtworkTravelsWithProviderMetadata() async throws {
        let data = Data(#"{"results":[{"id":7,"name":"Rain - Night","artist_name":"A - B","audio":"https://example.org/audio.mp3","image":"https://example.org/cover.jpg","license_ccurl":"https://creativecommons.org/licenses/by/4.0/"}]}"#.utf8)
        let parsed = try await OnlineCatalog().parseJamendo(data)
        let track = try XCTUnwrap(parsed.first)
        XCTAssertEqual(track.artworkURL?.absoluteString, "https://example.org/cover.jpg")
        XCTAssertEqual(track.title, "Rain - Night")
        XCTAssertEqual(track.artist, "A - B")
        XCTAssertEqual(track.previewSnapshot()?.sourceKind, .onlinePreview)
    }

    func testProviderWithoutArtworkStillProvidesPlayablePreview() async throws {
        let data = Data(#"{"results":[{"id":8,"name":"Rain","artist_name":"A","audio":"https://example.org/audio.mp3"}]}"#.utf8)
        let parsed = try await OnlineCatalog().parseJamendo(data)
        XCTAssertNil(parsed.first?.artworkURL)
        XCTAssertEqual(parsed.first?.previewSnapshot()?.title, "Rain")
        XCTAssertFalse(parsed.first!.license.allowsDownload)
    }

    func testOnlyOpenLicensedResultsCanBeDownloaded() {
        XCTAssertTrue(CatalogLicense.publicDomain.allowsDownload)
        XCTAssertTrue(CatalogLicense.creativeCommons(attribution: "CC BY 4.0").allowsDownload)
        XCTAssertFalse(CatalogLicense.unknown.allowsDownload)
    }

    func testCatalogResultUsesStableAudioFilename() {
        let result = CatalogTrack(id: "jamendo-1", title: "Rain / Night", artist: "A", audioURL: URL(string: "https://example.com/a.mp3")!, license: .publicDomain)
        XCTAssertEqual(result.safeFilename, "Rain - Night - A.mp3")
    }

    func testInternetArchiveSearchDocumentDecodesOpenLicenseMetadata() throws {
        let data = #"{"identifier":"archive-1","title":"Open Song","creator":"Artist","licenseurl":"https://creativecommons.org/licenses/by/4.0/"}"#.data(using: .utf8)!
        let document = try JSONDecoder().decode(OnlineCatalog.ArchiveDocument.self, from: data)
        XCTAssertEqual(document.identifier, "archive-1")
        XCTAssertEqual(document.licenseurl, "https://creativecommons.org/licenses/by/4.0/")
    }
}

private final class SearchFallbackProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let status: Int
        let json: String
        if url.host == "c.y.qq.com" {
            status = 200
            json = #"{"code":0,"data":{"song":{"list":[{"songmid":"qq-id","songname":"晴天","singer":[{"name":"周杰伦"}]}]}}}"#
        } else if url.host == "itunes.apple.com" {
            let country = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "country" }?.value
            status = country == "CN" ? 200 : 503
            json = #"{"resultCount":0,"results":[]}"#
        } else {
            status = 503
            json = "{}"
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
