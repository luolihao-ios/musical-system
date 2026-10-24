import XCTest

// 独立素材捕获：复用生产播放器，演示文案仅由 Debug 启动参数启用。
@MainActor
final class StoreAssetCaptureTests: XCTestCase {
    func testCaptureFourProductionPages() {
        let app = XCUIApplication()
        app.launchArguments = ["--adaptive-store-assets", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["player.compact.open"].waitForExistence(timeout: 15))
        save(app, name: "adaptive-01-local")
        app.buttons["player.compact.open"].tap()
        XCTAssertTrue(app.buttons["player.detail.playPause"].waitForExistence(timeout: 10))
        save(app, name: "adaptive-02-artwork")
        app.buttons["player.tab.lyrics"].tap()
        XCTAssertTrue(app.staticTexts["player.lyrics.line.0"].firstMatch.waitForExistence(timeout: 10))
        save(app, name: "adaptive-03-lyrics")
        app.buttons["player.detail.close"].tap()
        XCTAssertTrue(app.buttons["在线音乐"].waitForExistence(timeout: 10))
        app.buttons["在线音乐"].tap()
        XCTAssertTrue(app.staticTexts["演示搜索结果 · License unknown"].firstMatch.waitForExistence(timeout: 10))
        save(app, name: "adaptive-04-online")
    }
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
