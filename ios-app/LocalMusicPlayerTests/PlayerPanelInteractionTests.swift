import XCTest
@testable import LocalMusicPlayer

final class PlayerPanelInteractionTests: XCTestCase {
    func testEmptyPreferenceDoesNotEraseMeasuredPanelFrame() {
        let measured = CGRect(x: 0, y: 780, width: 402, height: 94)
        var value = CGRect.zero
        PlayerPanelFrameKey.reduce(value: &value, nextValue: { measured })
        PlayerPanelFrameKey.reduce(value: &value, nextValue: { .zero })
        XCTAssertEqual(value, measured)
    }
    func testEveryFingerPointChangesHeightByOnePointIncludingDirectionReversal() {
        var panel = PlayerPanelInteraction()
        for translation: CGFloat in [-10, -50, -180, -100, -20, 10, 25] {
            panel.drag(translation: translation, compact: 94, expanded: 800)
            XCTAssertEqual(panel.height(compact: 94, expanded: 800), 94 - translation, accuracy: 0.01)
            XCTAssertEqual(panel.phase, .compact, "松手前不能切换状态")
        }
    }

    func testUpwardReleaseAndRepeatedCallbacksOpenOnlyOnce() {
        var panel = PlayerPanelInteraction()
        panel.drag(translation: -180, compact: 94, expanded: 800)
        panel.expand() // 拖拽期间误收到点击不得再展开。
        XCTAssertEqual(panel.expansionCount, 0)
        panel.release(compact: 94, expanded: 800)
        panel.release(compact: 94, expanded: 800)
        panel.expand()
        XCTAssertEqual(panel.phase, .expanded)
        XCTAssertEqual(panel.expansionCount, 1)
    }

    func testCompactDownwardDragClosesOnlyOnReleasePastOneThird() {
        var panel = PlayerPanelInteraction()
        panel.drag(translation: 21, compact: 60, expanded: 800)
        XCTAssertEqual(panel.height(compact: 60, expanded: 800), 39)
        XCTAssertEqual(panel.phase, .compact)
        panel.release(compact: 60, expanded: 800)
        XCTAssertEqual(panel.phase, .hidden)
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
        XCTAssertEqual(panel.phase, .hidden)
    }
}
