import XCTest

@MainActor
final class AdaptivePlayerUITests: XCTestCase {
    func testProductionAudioPositionAndEngineSurviveRotation() {
        let app = XCUIApplication()
        app.launchArguments = ["--adaptive-store-assets", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let evidence = app.otherElements["fixture.realPlayback"]
        XCTAssertTrue(evidence.waitForExistence(timeout: 15))
        func sample() -> [String] { (evidence.value as? String ?? "").components(separatedBy: "|") }
        let running = NSPredicate { _, _ in
            let fields = sample()
            return fields.count == 3 && fields[2] == "true" && (Double(fields[1]) ?? 0) > 0.5
        }
        expectation(for: running, evaluatedWith: evidence)
        waitForExpectations(timeout: 15)
        let before = sample()
        app.buttons["player.compact.open"].tap()
        XCTAssertTrue(app.buttons["player.detail.playPause"].waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        let advances = NSPredicate { _, _ in
            let after = sample()
            return after.count == 3 && after[0] == before[0] && after[2] == "true"
                && (Double(after[1]) ?? 0) > (Double(before[1]) ?? 0) + 1
        }
        expectation(for: advances, evaluatedWith: evidence)
        waitForExpectations(timeout: 15)
        XCTAssertTrue(app.buttons["player.detail.playPause"].isHittable)
    }
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testPlayerKeepsPlaybackWhenWindowLayoutChanges() {
        let app = XCUIApplication()
        app.launchArguments = ["--player-interaction-tests", "--store-assets", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["player.compact.open"].waitForExistence(timeout: 10))
        app.buttons["player.compact.open"].tap()
        let play = app.buttons["player.detail.playPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        XCTAssertEqual(play.label, "暂停")
        let title = app.staticTexts["夜色慢行"].firstMatch
        XCTAssertTrue(title.exists)
        app.buttons["player.tab.lyrics"].tap()
        XCTAssertTrue(app.staticTexts["player.lyrics.line.0"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertEqual(play.label, "暂停", "旋转不能重建或暂停播放模型")
        XCTAssertTrue(title.exists)
        XCTAssertTrue(play.isHittable)
        if app.frame.width >= 720 && app.frame.height >= 500 {
            XCTAssertTrue(app.otherElements["player.layout.wide"].exists)
            XCTAssertTrue(app.otherElements["player.artwork"].exists)
        }
        app.buttons["player.detail.close"].tap()
        XCTAssertTrue(app.buttons["player.compact.open"].waitForExistence(timeout: 5))
        app.buttons["player.compact.open"].tap()
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertEqual(play.label, "暂停")
    }
}
