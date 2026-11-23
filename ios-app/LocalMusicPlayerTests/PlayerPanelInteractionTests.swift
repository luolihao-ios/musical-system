import XCTest
@testable import LocalMusicPlayer

final class PlayerPanelInteractionTests: XCTestCase {
    func testResizeRejectsRemainingCallbacksUntilGestureSessionEnds() {
        var panel = PlayerPanelInteraction()
        panel.expand()
        panel.drag(translation: 100, compact: 60, expanded: 1000)
        panel.cancelDragForResize()
        panel.drag(translation: 400, compact: 60, expanded: 650)
        panel.release(compact: 60, expanded: 650)
        XCTAssertEqual(panel.phase, .expanded)
        XCTAssertFalse(panel.acceptsGesture)
        XCTAssertEqual(panel.height(compact: 60, expanded: 650), 650)
        panel.finishGestureSession()
        panel.drag(translation: 250, compact: 60, expanded: 650)
        panel.release(compact: 60, expanded: 650)
        XCTAssertEqual(panel.phase, .compact)
    }
    func testResizeCancelsOldGestureHeightWithoutClosingOrReopening() {
        var panel = PlayerPanelInteraction()
        panel.expand()
        panel.drag(translation: 180, compact: 60, expanded: 1000)
        panel.cancelDragForResize()
        XCTAssertFalse(panel.isDragging)
        XCTAssertEqual(panel.phase, .expanded)
        XCTAssertEqual(panel.expansionCount, 1)
        XCTAssertEqual(panel.height(compact: 60, expanded: 650), 650)
    }
    func testEmptyPreferenceDoesNotEraseMeasuredPanelFrame() {
        let measured = CGRect(x: 0, y: 780, width: 402, height: 94)
        var value = CGRect.zero
        PlayerPanelFrameKey.reduce(value: &value, nextValue: { measured })
        PlayerPanelFrameKey.reduce(value: &value, nextValue: { .zero })
        XCTAssertEqual(value, measured)
    }
    func testExpandedDownwardDragTracksFingerIncludingDirectionReversal() {
        var panel = PlayerPanelInteraction()
        panel.expand()
        for translation: CGFloat in [10, 50, 180, 100, 20, 10, 25] {
            panel.drag(translation: translation, compact: 94, expanded: 800)
            XCTAssertEqual(panel.height(compact: 94, expanded: 800), 800 - translation, accuracy: 0.01)
            XCTAssertEqual(panel.phase, .expanded, "松手前不能切换状态")
        }
    }

    func testCompactSwipeDoesNotExpandAndRepeatedTapsOpenOnlyOnce() {
        var panel = PlayerPanelInteraction()
        panel.drag(translation: -180, compact: 94, expanded: 800)
        XCTAssertEqual(panel.expansionCount, 0)
        panel.release(compact: 94, expanded: 800)
        panel.release(compact: 94, expanded: 800)
        panel.expand()
        XCTAssertEqual(panel.phase, .expanded)
        XCTAssertEqual(panel.expansionCount, 1)
    }

    func testCompactDownwardDragNeverHidesPlayer() {
        var panel = PlayerPanelInteraction()
        panel.drag(translation: 21, compact: 60, expanded: 800)
        XCTAssertEqual(panel.height(compact: 60, expanded: 800), 60)
        XCTAssertEqual(panel.phase, .compact)
        panel.release(compact: 60, expanded: 800)
        XCTAssertEqual(panel.phase, .compact)
    }

    func testExpandedCloseThresholdUsesHeightAtTouchDown() {
        var panel = PlayerPanelInteraction()
        panel.expand()
        panel.drag(translation: 250, compact: 94, expanded: 780)
        panel.release(compact: 94, expanded: 780)
        XCTAssertEqual(panel.phase, .expanded)
        panel.drag(translation: 261, compact: 94, expanded: 780)
        XCTAssertEqual(panel.phase, .expanded)
        panel.release(compact: 94, expanded: 780)
        XCTAssertEqual(panel.phase, .compact)
        panel.expand()
        XCTAssertEqual(panel.phase, .expanded)
    }
}
