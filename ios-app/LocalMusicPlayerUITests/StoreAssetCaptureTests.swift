import XCTest

// 独立素材捕获：复用生产播放器，演示文案仅由 Debug 启动参数启用。
@MainActor
final class StoreAssetCaptureTests: XCTestCase {
    func testCaptureArtworkAndLyrics() {
        let app = XCUIApplication()
        app.launchArguments = ["--player-interaction-tests", "--store-assets"]
        app.launch()
        XCTAssertTrue(app.buttons["player.compact.open"].waitForExistence(timeout: 10))
        app.buttons["player.compact.open"].tap()
        XCTAssertTrue(app.buttons["player.lyrics.snippet"].waitForExistence(timeout: 10))
        save(app, name: "ipad-artwork")
        app.buttons["player.tab.lyrics"].tap()
        XCTAssertTrue(app.staticTexts["player.lyrics.line.0"].waitForExistence(timeout: 10))
        save(app, name: "ipad-lyrics")
    }

    private func save(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
