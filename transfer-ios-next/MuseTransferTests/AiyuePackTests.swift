import XCTest
@testable import AiyueTransfer

final class AiyuePackTests: XCTestCase {
    func testMP3OnlyPackageRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audio = root.appendingPathComponent("歌曲.MP3")
        try Data("audio".utf8).write(to: audio)
        let packages = try MusicPackage.create(files: [audio], destination: root.appendingPathComponent("packs"))
        let (manifest, files) = try MusicPackage.extract(packages[0], to: root.appendingPathComponent("unpack"))
        XCTAssertNil(manifest.lyricsPath); XCTAssertNil(manifest.coverPath)
        XCTAssertEqual(files.count, 1); XCTAssertEqual(try Data(contentsOf: files[0]), Data("audio".utf8))
    }
    func testManifestRoundTrips() throws {
        let source = AiyuePackManifest(title: "song", artist: "artist", audioPath: "audio/song.mp3", lyricsPath: "lyrics/song.lrc", coverPath: "cover/song.jpg")
        let restored = try JSONDecoder().decode(AiyuePackManifest.self, from: AiyuePack.manifestData(source))
        XCTAssertEqual(source, restored)
    }
}
