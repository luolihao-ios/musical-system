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

    // XCTest 的同步 tearDownWithError 不隔离到 MainActor；在界面测试作用域内收集证据。
    private func attachEvidence() {
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "播放器控件状态"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        attachScreenshot("测试结束界面")
    }

    private func waitForPhase(_ phase: String) {
        let predicate = NSPredicate(format: "value BEGINSWITH %@", phase)
        expectation(for: predicate, evaluatedWith: panel)
        waitForExpectations(timeout: 5)
    }

    func testPlayerSitsAboveMenuAndPlaybackButtonDoesNotTapThrough() {
        defer { attachEvidence() }
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        XCTAssertLessThan(app.buttons["player.compact.playback"].frame.maxY, app.tabBars.firstMatch.frame.minY)
        app.buttons["player.compact.playback"].tap()
        expectation(for: NSPredicate(format: "value == 'playing'"), evaluatedWith: app.buttons["player.compact.playback"])
        waitForExpectations(timeout: 3)
        XCTAssertTrue(app.staticTexts["底层点击次数 0"].exists)
        attachScreenshot("紧凑播放器贴底")
    }

    func testCompactSwipeDoesNotExpandThenTapOpensAndDownwardReleaseCollapses() {
        defer { attachEvidence() }
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        let start = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 24))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -220)))
        waitForPhase("compact")
        app.buttons["player.compact.open"].tap()
        waitForPhase("expanded")
        XCTAssertEqual(panel.value as? String, "expanded;expansions=1")
        XCTAssertEqual(app.sheets.count, 0)
        XCTAssertEqual(app.otherElements.matching(identifier: "player.panel").count, 1)
        XCTAssertEqual(panel.frame.maxY, app.frame.maxY, accuracy: 1)
        attachScreenshot("同一面板展开")
        let header = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 26))
        header.press(forDuration: 0.1, thenDragTo: header.withOffset(CGVector(dx: 0, dy: panel.frame.height * 0.4)))
        waitForPhase("compact")
        XCTAssertTrue(app.buttons["player.compact.playback"].isHittable)
    }

    func testCompactDownwardReleaseKeepsPlayerVisible() {
        defer { attachEvidence() }
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        let start = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 16))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: panel.frame.height * 0.4)))
        waitForPhase("compact")
        XCTAssertTrue(app.buttons["player.compact.open"].isHittable)
    }

    func testTapExpandsAndShortDownwardDragReturnsToExpanded() {
        defer { attachEvidence() }
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        app.buttons["player.compact.open"].tap()
        waitForPhase("expanded")
        let start = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 26))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 80)))
        waitForPhase("expanded")
        XCTAssertEqual(panel.value as? String, "expanded;expansions=1")
        app.buttons["player.detail.close"].tap()
        waitForPhase("compact")
        app.buttons["player.compact.open"].tap()
        waitForPhase("expanded")
    }

    func testLyricsReturnToArtworkAndQueueControlsRemainUsable() {
        defer { attachEvidence() }
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        app.buttons["player.compact.open"].tap()
        waitForPhase("expanded")
        XCTAssertTrue(app.buttons["player.lyrics.snippet"].waitForExistence(timeout: 5))
        app.buttons["player.lyrics.snippet"].tap()
        XCTAssertTrue(app.staticTexts["player.lyrics.line.1"].waitForExistence(timeout: 3))
        app.staticTexts["player.lyrics.line.1"].tap()
        XCTAssertTrue(app.staticTexts["00:00"].exists, "点击歌词不得跳转到第二句的 00:10")
        app.buttons["player.tab.song"].tap()
        XCTAssertTrue(app.buttons["player.lyrics.snippet"].waitForExistence(timeout: 3))
        app.buttons["player.detail.queue"].tap()
        XCTAssertTrue(app.buttons["player.queue.clear"].waitForExistence(timeout: 3))
    }

    func testArtworkSwipeUpAdvancesWithoutClosingDetail() {
        defer { attachEvidence() }
        app.buttons["player.compact.open"].tap()
        waitForPhase("expanded")
        let artwork = app.otherElements["player.artwork"].firstMatch
        XCTAssertTrue(artwork.waitForExistence(timeout: 5))
        artwork.swipeUp()
        waitForPhase("expanded")
        XCTAssertTrue(app.staticTexts["00:10"].waitForExistence(timeout: 3))
    }

    func testSongRowBlankSpacePlaysButFavoriteDoesNot() {
        defer { attachEvidence() }
        let row = app.buttons.matching(identifier: "fixture.songRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["底层点击次数 1"].exists)
        app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "fixture.songRow", "收藏")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["底层点击次数 1"].exists)
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
