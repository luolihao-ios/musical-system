import ImageIO
import XCTest
@testable import LocalMusicPlayer

@MainActor
final class ProceduralArtworkGeneratorTests: XCTestCase {
    func testGeneratedArtworkIsDecodableOpaqueSquareJPEG() throws {
        let generator = ProceduralArtworkGenerator()

        let data = try generator.generateArtwork(
            title: "夜航星",
            artist: "测试歌手",
            seed: "track-001"
        )

        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.jpeg")
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 768)
        XCTAssertEqual(image.height, 768)
        XCTAssertFalse(
            image.alphaInfo == .first
                || image.alphaInfo == .last
                || image.alphaInfo == .premultipliedFirst
                || image.alphaInfo == .premultipliedLast
        )
    }

    func testGeneratedArtworkIsStableForSameTrackAndVariesBySeed() throws {
        let generator = ProceduralArtworkGenerator()

        let first = try generator.generateArtwork(
            title: "同名歌曲",
            artist: "同一歌手",
            seed: "track-001"
        )
        let repeated = try generator.generateArtwork(
            title: "同名歌曲",
            artist: "同一歌手",
            seed: "track-001"
        )
        let anotherTrack = try generator.generateArtwork(
            title: "同名歌曲",
            artist: "同一歌手",
            seed: "track-002"
        )

        XCTAssertEqual(first, repeated)
        XCTAssertNotEqual(first, anotherTrack)
    }
}
