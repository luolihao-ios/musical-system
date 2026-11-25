import XCTest

// 独立素材捕获：复用生产播放器，演示文案仅由 Debug 启动参数启用。
@MainActor
final class StoreAssetCaptureTests: XCTestCase {
    func testCaptureFourProductionPages() {
        let app = XCUIApplication()
        app.launchArguments = ["--adaptive-store-assets", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["player.compact.open"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["discovery.track.demo-online-0"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["personal.import"].exists)
        app.buttons["音乐库"].firstMatch.tap()
        XCTAssertTrue(app.buttons["personal.import"].waitForExistence(timeout: 10))
        save(app, name: "adaptive-01-local")
        app.buttons["player.compact.open"].tap()
        XCTAssertTrue(app.buttons["player.detail.playPause"].waitForExistence(timeout: 10))
        save(app, name: "adaptive-02-artwork")
        XCUIDevice.shared.orientation = .landscapeLeft
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        XCTAssertTrue(app.buttons["player.detail.playPause"].waitForExistence(timeout: 10))
        save(app, name: "adaptive-05-landscape-nowplaying")
        XCUIDevice.shared.orientation = .portrait
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        app.buttons["player.tab.lyrics"].tap()
        XCTAssertTrue(app.staticTexts["player.lyrics.line.0"].firstMatch.waitForExistence(timeout: 10))
        save(app, name: "adaptive-03-lyrics")
        app.buttons["player.detail.close"].tap()
        XCTAssertTrue(app.buttons["搜索"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["搜索"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["演示搜索结果 · 许可未知"].firstMatch.waitForExistence(timeout: 10))
        save(app, name: "adaptive-04-online")
        XCUIDevice.shared.press(.home)
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
