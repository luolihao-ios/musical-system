import XCTest

@MainActor
final class LocalizationUITests: XCTestCase {
    func testFrenchSystemLanguageTranslatesHomePlayerAndSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--adaptive-store-assets", "-AppleLanguages", "(fr-FR)", "-AppleLocale", "fr_FR"]
        app.launch()
        XCTAssertTrue(app.buttons["player.compact.open"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Musique locale"].exists)
        app.buttons["player.compact.open"].tap()
        XCTAssertTrue(app.buttons["player.tab.song"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["player.tab.song"].label, "Chanson")
        XCTAssertEqual(app.buttons["player.tab.lyrics"].label, "Paroles")
        XCTAssertEqual(app.buttons["player.detail.playPause"].label, "Pause")
        XCTAssertEqual(app.buttons["player.detail.close"].label, "Réduire le lecteur")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "french-player"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["player.detail.close"].tap()
        let settings = app.buttons["Réglages"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.staticTexts["Confidentialité"].firstMatch.waitForExistence(timeout: 5))
    }
}
