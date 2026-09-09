import UIKit
import XCTest
@testable import LocalMusicPlayer

@MainActor
final class ArtworkImageLoaderTests: XCTestCase {
    func testArtworkLoaderDownsamplesLargeArtworkForPlaybackSurfaces() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let source = UIGraphicsImageRenderer(
            size: CGSize(width: 2048, height: 2048)
        ).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2048, height: 2048))
        }
        let path = root.appendingPathComponent("artwork.png")
        try source.write(to: path)

        let image = try XCTUnwrap(
            ArtworkImageLoader.image(atPath: path.path, maxPixelSize: 512)
        )
        XCTAssertLessThanOrEqual(image.size.width, 512)
        XCTAssertLessThanOrEqual(image.size.height, 512)
    }
}
