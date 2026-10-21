import XCTest
@testable import LocalMusicPlayer

final class CrashDiagnosticsTests: XCTestCase {
    func testTimestampExplicitlyUsesBeijingTime() {
        XCTAssertEqual(DiagnosticTimestamp.string(Date(timeIntervalSince1970: 0)), "1970-01-01T08:00:00.000+08:00")
    }

    func testExceptionReportIsWrittenToDocumentsWithoutInventingStack() throws {
        let url = CrashExceptionDiagnostics.fileURL
        let previous = try? Data(contentsOf: url)
        defer {
            if let previous { try? previous.write(to: url) }
            else { try? FileManager.default.removeItem(at: url) }
        }
        let exception = NSException(name: NSExceptionName("TestException"), reason: "测试异常原因", userInfo: nil)
        CrashExceptionDiagnostics.record(exception)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("name=TestException reason=测试异常原因"))
        XCTAssertTrue(text.contains("+08:00"))
        XCTAssertTrue(text.contains("version="))
        XCTAssertTrue(text.contains("exceptionStack:"))
        XCTAssertTrue(text.contains("异常未提供原始堆栈"))
    }
}
