import XCTest
@testable import LocalMusicPlayer

final class NowPlayingContentModeTests: XCTestCase {
    private let lines = [
        LyricLine(timestamp: 0, text: "开场"),
        LyricLine(timestamp: 4, text: " "),
        LyricLine(timestamp: 8, text: "正在唱的这一句"),
        LyricLine(timestamp: 12, text: "下一句"),
        LyricLine(timestamp: 16, text: "尾声")
    ]

    func testSnippetFollowsCurrentLineAndShowsNextNonemptyLine() {
        XCTAssertEqual(
            NowPlayingLyricSnippet.lines(from: lines, currentIndex: 2).map(\.text),
            ["正在唱的这一句", "下一句"]
        )
        XCTAssertEqual(
            NowPlayingLyricSnippet.lines(from: lines, currentIndex: 0).map(\.text),
            ["开场", "正在唱的这一句"]
        )
    }

    func testSnippetBeforeFirstTimestampShowsUpcomingLines() {
        XCTAssertEqual(
            NowPlayingLyricSnippet.lines(from: lines, currentIndex: nil).map(\.text),
            ["开场", "正在唱的这一句"]
        )
    }

    func testSnippetAtEndDoesNotRepeatEarlierLines() {
        XCTAssertEqual(
            NowPlayingLyricSnippet.lines(from: lines, currentIndex: 4).map(\.text),
            ["尾声"]
        )
    }

    func testSnippetHandlesEmptyAndOutOfDateIndexesWithoutCrashing() {
        XCTAssertTrue(NowPlayingLyricSnippet.lines(from: [], currentIndex: 0).isEmpty)
        XCTAssertTrue(NowPlayingLyricSnippet.lines(from: lines, currentIndex: 99).isEmpty)
        XCTAssertEqual(
            NowPlayingLyricSnippet.lines(from: lines, currentIndex: -1).map(\.text),
            ["开场", "正在唱的这一句"]
        )
    }
}
