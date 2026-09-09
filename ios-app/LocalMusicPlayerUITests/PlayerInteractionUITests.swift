import XCTest

@MainActor
final class PlayerInteractionUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--player-interaction-tests"]
        app.launch()
    }

    private var panel: XCUIElement { app.otherElements["player.panel"].firstMatch }

    private func waitForPhase(_ phase: String) {
        let predicate = NSPredicate(format: "value BEGINSWITH %@", phase)
        expectation(for: predicate, evaluatedWith: panel)
        waitForExpectations(timeout: 5)
    }

    func testBottomEdgeTouchesWindowAndPlaybackButtonDoesNotTapThrough() {
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        XCTAssertEqual(panel.frame.maxY, app.frame.maxY, accuracy: 1)
        app.buttons["player.compact.playback"].tap()
        expectation(for: NSPredicate(format: "value == 'playing'"), evaluatedWith: app.buttons["player.compact.playback"])
        waitForExpectations(timeout: 3)
        XCTAssertTrue(app.staticTexts["底层点击次数 0"].exists)
        attachScreenshot("紧凑播放器贴底")
    }

    func testUpwardDragExpandsOnePanelWithoutSheetThenDownwardReleaseCloses() {
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        let start = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 24))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -220)))
        waitForPhase("expanded")
        XCTAssertEqual(panel.value as? String, "expanded;expansions=1")
        XCTAssertEqual(app.sheets.count, 0)
        XCTAssertEqual(app.otherElements.matching(identifier: "player.panel").count, 1)
        XCTAssertEqual(panel.frame.maxY, app.frame.maxY, accuracy: 1)
        attachScreenshot("同一面板展开")
        let header = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 26))
        header.press(forDuration: 0.1, thenDragTo: header.withOffset(CGVector(dx: 0, dy: panel.frame.height * 0.4)))
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: panel)
        waitForExpectations(timeout: 5)
    }

    func testCompactDownwardReleaseDismissesAndCanBeShownAgain() {
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        let start = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 16))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: panel.frame.height * 0.4)))
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: panel)
        waitForExpectations(timeout: 5)
        app.buttons["重新显示播放器"].tap()
        waitForPhase("compact")
        XCTAssertEqual(panel.frame.maxY, app.frame.maxY, accuracy: 1)
    }

    func testTapExpandsAndShortDownwardDragReturnsToExpanded() {
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        app.buttons["player.compact.open"].tap()
        waitForPhase("expanded")
        let start = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 26))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 80)))
        waitForPhase("expanded")
        XCTAssertEqual(panel.value as? String, "expanded;expansions=1")
        app.buttons["player.detail.close"].tap()
        XCTAssertFalse(panel.exists)
    }

    func testLyricsReturnToArtworkAndQueueControlsRemainUsable() {
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        app.buttons["player.compact.open"].tap()
        waitForPhase("expanded")
        XCTAssertTrue(app.buttons["player.artwork"].waitForExistence(timeout: 5))
        app.buttons["player.artwork"].tap()
        XCTAssertTrue(app.buttons["player.lyrics.artwork"].waitForExistence(timeout: 3))
        app.buttons["player.lyrics.artwork"].tap()
        XCTAssertTrue(app.buttons["player.artwork"].waitForExistence(timeout: 3))
        app.buttons["player.detail.queue"].tap()
        XCTAssertTrue(app.buttons["player.queue.clear"].waitForExistence(timeout: 3))
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
