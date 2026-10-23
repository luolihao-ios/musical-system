import UIKit
import XCTest
@testable import LocalMusicPlayer

final class NowPlayingArtworkThemeTests: XCTestCase {
    func testDominantCoverColorWinsOverSmallContrastingAccent() {
        let blue = ArtworkRGB(red: 0.15, green: 0.4, blue: 0.9)
        let red = ArtworkRGB(red: 0.9, green: 0.1, blue: 0.1)
        let theme = NowPlayingArtworkTheme.from(pixels: Array(repeating: blue, count: 80) + Array(repeating: red, count: 20))
        XCTAssertGreaterThan(theme.top.blue, theme.top.red)
        XCTAssertGreaterThan(theme.bottom.blue, theme.bottom.red)
    }

    func testVeryDarkCoverStillProducesColoredBackgroundInsteadOfBlack() {
        let theme = NowPlayingArtworkTheme.from(pixels: [ArtworkRGB(red: 0.03, green: 0.08, blue: 0.12)])
        XCTAssertGreaterThan(max(theme.top.red, theme.top.green, theme.top.blue), 0.55)
        XCTAssertGreaterThan(max(theme.bottom.red, theme.bottom.green, theme.bottom.blue), 0.55)
        XCTAssertGreaterThan(theme.top.blue, theme.top.red)
    }

    func testGeneratedRecordCoverKeepsItsColoredPaletteInsteadOfBlackDisc() {
        let blackDisc = ArtworkRGB(red: 0.018, green: 0.018, blue: 0.018)
        let greenBackground = ArtworkRGB(red: 0.05, green: 0.22, blue: 0.09)
        let theme = NowPlayingArtworkTheme.from(pixels: Array(repeating: blackDisc, count: 65) + Array(repeating: greenBackground, count: 35))
        XCTAssertGreaterThan(theme.top.green, theme.top.red)
        XCTAssertGreaterThan(theme.top.green, theme.top.blue)
    }

    func testForegroundIsReadableAgainstBothGradientStopsForVariedCovers() {
        let covers: [ArtworkRGB] = [
            .init(red: 1, green: 0.9, blue: 0),
            .init(red: 0, green: 0, blue: 1),
            .init(red: 1, green: 0, blue: 0),
            .init(red: 0, green: 1, blue: 0),
            .init(red: 0, green: 0, blue: 0),
            .init(red: 1, green: 1, blue: 1),
            .init(red: 0.5, green: 0.5, blue: 0.5)
        ]
        for cover in covers {
            let theme = NowPlayingArtworkTheme.from(pixels: [cover])
            XCTAssertGreaterThanOrEqual(theme.foreground.contrast(with: theme.top), 4.5)
            XCTAssertGreaterThanOrEqual(theme.foreground.contrast(with: theme.bottom), 4.5)
        }
    }

    func testMissingArtworkUsesStableFallback() {
        XCTAssertEqual(NowPlayingArtworkTheme.from(pixels: []), .fallback)
        XCTAssertEqual(NowPlayingArtworkTheme.load(atPath: nil), .fallback)
        XCTAssertEqual(NowPlayingArtworkTheme.load(atPath: "/missing/cover.jpg"), .fallback)
    }

    @MainActor
    func testArtworkFileSamplingUsesActualCoverPixels() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        defer { try? FileManager.default.removeItem(at: path) }
        let data = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512)).pngData { context in
            UIColor(red: 0.1, green: 0.75, blue: 0.25, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
        }
        try data.write(to: path)
        let theme = NowPlayingArtworkTheme.load(atPath: path.path)
        XCTAssertGreaterThan(theme.top.green, theme.top.red)
        XCTAssertGreaterThan(theme.top.green, theme.top.blue)
    }

    @MainActor
    func testTransparentArtworkUsesFallbackRatherThanPremultipliedBlack() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        defer { try? FileManager.default.removeItem(at: path) }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let data = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48), format: format).pngData { _ in }
        try data.write(to: path)
        XCTAssertEqual(NowPlayingArtworkTheme.load(atPath: path.path), .fallback)
    }
}
