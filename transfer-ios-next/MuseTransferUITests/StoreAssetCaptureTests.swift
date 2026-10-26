import XCTest
import UIKit

@MainActor
final class StoreAssetCaptureTests: XCTestCase {
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testFiveProductionTransferPagesFillDevice() {
        for page in ["connect", "receive", "send", "edit", "completed"] {
            let app = XCUIApplication()
            app.launchArguments = ["--file-send-store-page", page, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
            app.launch()
            XCTAssertTrue(app.staticTexts["transfer.address"].waitForExistence(timeout: 15))
            if UIDevice.current.userInterfaceIdiom == .pad {
                XCTAssertGreaterThan(app.frame.width, 700, "iPad 必须作为原生平板 App 运行")
            }
            let content = app.scrollViews["transfer.content"].firstMatch
            XCTAssertTrue(content.exists)
            XCTAssertGreaterThan(content.frame.width, app.frame.width * 0.9)
            if page == "send" || page == "edit" {
                XCTAssertTrue(app.buttons["transfer.send"].exists)
                XCTAssertTrue(app.staticTexts["会议记录.pdf"].exists)
            }
            save(app, name: "filesend-" + page)
            if page == "connect" {
                XCUIDevice.shared.orientation = .landscapeLeft
                XCTAssertTrue(app.staticTexts["transfer.address"].isHittable)
                save(app, name: "filesend-landscape")
                XCUIDevice.shared.orientation = .portrait
            }
            app.terminate()
        }
    }

    private func save(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
