import XCTest
@testable import LocalMusicPlayer

final class OnlineCatalogTests: XCTestCase {
    func testOnlyOpenLicensedResultsCanBeDownloaded() {
        XCTAssertTrue(CatalogLicense.publicDomain.allowsDownload)
        XCTAssertTrue(CatalogLicense.creativeCommons(attribution: "CC BY 4.0").allowsDownload)
        XCTAssertFalse(CatalogLicense.unknown.allowsDownload)
    }

    func testCatalogResultUsesStableAudioFilename() {
        let result = CatalogTrack(id: "jamendo-1", title: "Rain / Night", artist: "A", audioURL: URL(string: "https://example.com/a.mp3")!, license: .publicDomain)
        XCTAssertEqual(result.safeFilename, "Rain - Night - A.mp3")
    }
}
