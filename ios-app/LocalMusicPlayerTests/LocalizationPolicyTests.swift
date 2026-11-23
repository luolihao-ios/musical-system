import XCTest
@testable import LocalMusicPlayer

final class LocalizationPolicyTests: XCTestCase {
    func testSupportedLanguageMapping() {
        XCTAssertEqual(AppLanguage(localeIdentifier: "zh-Hans-CN"), .simplifiedChinese)
        XCTAssertEqual(AppLanguage(localeIdentifier: "zh-Hant-TW"), .traditionalChinese)
        XCTAssertEqual(AppLanguage(localeIdentifier: "en-US"), .english)
        XCTAssertEqual(AppLanguage(localeIdentifier: "fr-FR"), .french)
        XCTAssertEqual(AppLanguage(localeIdentifier: "fr_CA"), .french)
        XCTAssertEqual(AppLanguage(localeIdentifier: "fr"), .french)
    }

    func testUnsupportedLanguagesFallBackToEnglish() {
        XCTAssertEqual(AppLanguage(localeIdentifier: "de-DE"), .english)
        XCTAssertEqual(AppLanguage(localeIdentifier: "ja-JP"), .english)
    }

    func testFrenchBundleResolvesControlsAndPermissionDescription() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "fr", ofType: "lproj"))
        let bundle = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(bundle.localizedString(forKey: "音乐库", value: nil, table: nil), "Bibliothèque")
        XCTAssertEqual(bundle.localizedString(forKey: "收藏", value: nil, table: nil), "Favoris")
        XCTAssertEqual(bundle.localizedString(forKey: "查找歌词", value: nil, table: nil), "Rechercher les paroles")
        XCTAssertTrue(bundle.localizedString(forKey: "NSAppleMusicUsageDescription", value: nil, table: "InfoPlist").contains("musique"))
    }
}
