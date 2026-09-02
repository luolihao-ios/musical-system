import XCTest
@testable import AiyueTransfer

final class AiyuePackTests: XCTestCase {
    func testManifestRoundTrips() throws {
        let source = AiyuePackManifest(title: "song", artist: "artist", audioPath: "audio/song.mp3", lyricsPath: "lyrics/song.lrc", coverPath: "cover/song.jpg")
        let restored = try JSONDecoder().decode(AiyuePackManifest.self, from: AiyuePack.manifestData(source))
        XCTAssertEqual(source, restored)
    }
}
