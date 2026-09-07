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

    func testInternetArchiveSearchDocumentDecodesOpenLicenseMetadata() throws {
        let data = #"{"identifier":"archive-1","title":"Open Song","creator":"Artist","licenseurl":"https://creativecommons.org/licenses/by/4.0/"}"#.data(using: .utf8)!
        let document = try JSONDecoder().decode(OnlineCatalog.ArchiveDocument.self, from: data)
        XCTAssertEqual(document.identifier, "archive-1")
        XCTAssertEqual(document.licenseurl, "https://creativecommons.org/licenses/by/4.0/")
    }
}
