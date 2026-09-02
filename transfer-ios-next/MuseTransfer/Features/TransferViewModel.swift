import Foundation
import SwiftUI
import Observation
import UIKit

@Observable final class TransferViewModel {
    var devices: [NearbyDevice] = []
    var selectedFiles: [URL] = []
    var showImporter = false
    var incomingTransfer: IncomingTransfer?
    var selectedSummary: String { selectedFiles.isEmpty ? "尚未选择文件" : "已选择 \(selectedFiles.count) 个文件" }
    private let browser: BonjourDeviceBrowser
    private let receiver: LocalSendReceiver
    private let local: DeviceInfo
    init() {
        local = DeviceInfo(alias: UIDevice.current.name, deviceModel: "iPhone", deviceType: "mobile", fingerprint: UUID().uuidString)
        browser = BonjourDeviceBrowser(localFingerprint: local.fingerprint)
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("爱乐互传", isDirectory: true)
        receiver = LocalSendReceiver(local: local, destination: folder)
        receiver.onIncomingTransfer = { [weak self] request in Task { @MainActor in self?.incomingTransfer = request } }
        do { try receiver.start() } catch { DiagnosticLog.write("iOS receiver start failed: \(error.localizedDescription)") }
        browser.onDevicesChanged = { [weak self] devices in Task { @MainActor in self?.devices = devices } }
        browser.start()
    }
    func refresh() { DiagnosticLog.write("User requested discovery refresh."); browser.stop(); browser.start() }
    func select(_ result: Result<[URL], Error>) { if case let .success(urls) = result { selectedFiles = urls } }
    func send(to device: NearbyDevice) {
        guard !selectedFiles.isEmpty else { return }
        Task { try? await BonjourLocalSendSender().send(files: selectedFiles, to: device, local: local) }
    }
    func decideIncoming(_ accepted: Bool) { guard let request = incomingTransfer else { return }; receiver.decide(sessionID: request.id, accepted: accepted); incomingTransfer = nil }
}

public struct NearbyDevice: Identifiable, Hashable { public let id: String; public let alias: String; public let deviceType: String; public let serviceName: String; public let serviceType: String; public let serviceDomain: String }
