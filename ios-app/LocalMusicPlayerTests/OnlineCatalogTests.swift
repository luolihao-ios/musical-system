import XCTest
@testable import LocalMusicPlayer

final class OnlineCatalogTests: XCTestCase {
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
