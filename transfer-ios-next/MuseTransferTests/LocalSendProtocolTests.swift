import XCTest
@testable import AiyueTransfer

final class LocalSendProtocolTests: XCTestCase {
    func testDeviceInfoUsesLocalSendFieldNames() throws {
        let data = try JSONEncoder().encode(DeviceInfo(alias: "爱乐互传", deviceModel: "iPhone", deviceType: "mobile", fingerprint: "fp"))
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"alias\"")); XCTAssertTrue(json.contains("\"deviceType\"")); XCTAssertTrue(json.contains("\"protocol\""))
    }
}
