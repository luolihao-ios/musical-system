import Foundation
import SwiftUI
import Observation
import UIKit

@Observable final class TransferViewModel {
    var devices: [NearbyDevice] = []
    var selectedFiles: [URL] = []
    var showImporter = false
    var selectedSummary: String { selectedFiles.isEmpty ? "尚未选择文件" : "已选择 \(selectedFiles.count) 个文件" }
    private let browser = BonjourDeviceBrowser()
    init() {
        browser.onDevicesChanged = { [weak self] devices in Task { @MainActor in self?.devices = devices } }
        browser.start()
    }
    func refresh() { browser.stop(); browser.start() }
    func select(_ result: Result<[URL], Error>) { if case let .success(urls) = result { selectedFiles = urls } }
    func send(to device: NearbyDevice) {
        guard !selectedFiles.isEmpty else { return }
        Task { try? await BonjourLocalSendSender().send(files: selectedFiles, to: device, local: DeviceInfo(alias: UIDevice.current.name, deviceModel: "iPhone", deviceType: "mobile", fingerprint: UUID().uuidString)) }
    }
}

public struct NearbyDevice: Identifiable, Hashable { public let id: String; public let alias: String; public let deviceType: String; public let serviceName: String; public let serviceType: String; public let serviceDomain: String }
