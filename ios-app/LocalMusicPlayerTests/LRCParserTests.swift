import XCTest
@testable import LocalMusicPlayer

final class LRCParserTests: XCTestCase {
    func testParsesFractionsMultipleTimestampsAndSorts() {
        let source = """
        [ar:测试歌手]
        [00:10.345][00:20.34]副歌
        [00:01.05]第一句
        malformed
        """

        let lines = LRCParser.parse(source)

        XCTAssertEqual(lines.map(\.text), ["第一句", "副歌", "副歌"])
        XCTAssertEqual(lines[0].timestamp, 1.05, accuracy: 0.0001)
        XCTAssertEqual(lines[1].timestamp, 10.345, accuracy: 0.0001)
        XCTAssertEqual(lines[2].timestamp, 20.34, accuracy: 0.0001)
    }

    func testCurrentIndexHandlesBeforeFirstAndAfterLastTimestamp() {
        let lines = [
            LyricLine(timestamp: 5, text: "第一句"),
            LyricLine(timestamp: 12, text: "第二句")
        ]

        XCTAssertNil(LRCParser.currentIndex(lines: lines, position: 2))
        XCTAssertEqual(LRCParser.currentIndex(lines: lines, position: 5), 0)
        XCTAssertEqual(LRCParser.currentIndex(lines: lines, position: 99), 1)
    }

    func testMalformedInputReturnsEmptyArray() {
        XCTAssertTrue(LRCParser.parse("not an lrc file").isEmpty)
    }
}
