import XCTest
@testable import LocalMusicPlayer

final class LocalizationPolicyTests: XCTestCase {
    func testSupportedLanguageMapping() {
        XCTAssertEqual(AppLanguage(localeIdentifier: "zh-Hans-CN"), .simplifiedChinese)
        XCTAssertEqual(AppLanguage(localeIdentifier: "zh-Hant-TW"), .traditionalChinese)
        XCTAssertEqual(AppLanguage(localeIdentifier: "en-US"), .english)
    }

    func testUnsupportedLanguagesFallBackToEnglish() {
        XCTAssertEqual(AppLanguage(localeIdentifier: "fr-FR"), .english)
        XCTAssertEqual(AppLanguage(localeIdentifier: "ja-JP"), .english)
    }
}
