import XCTest
@testable import AiyueTransfer

final class WebStaticAssetsTests: XCTestCase {
    func testLoginPageCanLoadTranslationScriptBeforeAuthentication() {
        XCTAssertEqual(WebStaticAssets.filename(for: "/i18n.js"), "i18n.js")
        XCTAssertEqual(WebStaticAssets.filename(for: "/"), "index.html")
        XCTAssertNil(WebStaticAssets.filename(for: "/../Info.plist"))
        XCTAssertNil(WebStaticAssets.filename(for: "/web/diagnostics"))
    }
}
