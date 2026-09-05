import Foundation
import SwiftUI
import Observation
import UIKit

@Observable final class TransferViewModel {
    var devices: [NearbyDevice] = []
    var selectedFiles: [URL] = []
    var showImporter = false
    var showEditor = false
    var incomingTransfer: IncomingTransfer?
    var showSelectionWarning = false
    var isSending = false
    var sendStatus: String?
    var selectedSummary: String {
        guard !selectedFiles.isEmpty else { return "尚未选择文件" }
        let total = selectedFiles.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return "文件：\(selectedFiles.count)  ·  大小：\(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
    }
    private let browser: BonjourDeviceBrowser
    private let receiver: LocalSendReceiver
    private let local: DeviceInfo
    init() {
        let key = "aiyue.transfer.deviceFingerprint"
        let fingerprint = UserDefaults.standard.string(forKey: key) ?? UUID().uuidString
        UserDefaults.standard.set(fingerprint, forKey: key)
        local = DeviceInfo(alias: UIDevice.current.name, deviceModel: "iPhone", deviceType: "mobile", fingerprint: fingerprint)
        browser = BonjourDeviceBrowser(localFingerprint: local.fingerprint)
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("爱乐互传", isDirectory: true)
        receiver = LocalSendReceiver(local: local, destination: folder)
        receiver.onIncomingTransfer = { [weak self] request in Task { @MainActor in self?.incomingTransfer = request } }
        do { try receiver.start() } catch { DiagnosticLog.write("iOS receiver start failed: \(error.localizedDescription)") }
        browser.onDevicesChanged = { [weak self] devices in Task { @MainActor in self?.devices = devices } }
        browser.start()
    }
    // Restarting NWListener to refresh Bonjour races with the old TCP socket being
    // released. It caused address-in-use failures and made a previously working
    // iOS advertisement disappear. Refreshing the browser is sufficient here.
    func refresh() { DiagnosticLog.write("User requested discovery refresh."); browser.stop(); browser.start() }
    func select(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result else { return }
        let outgoing = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("爱乐互传/待发送", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outgoing, withIntermediateDirectories: true)
            selectedFiles = try urls.map { source in
                guard source.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
                defer { source.stopAccessingSecurityScopedResource() }
                let target = outgoing.appendingPathComponent("\(UUID().uuidString)-\(source.lastPathComponent)")
                try FileManager.default.copyItem(at: source, to: target)
                return target
            }
            sendStatus = nil
        } catch {
            selectedFiles = []
            sendStatus = "无法读取所选文件：\(error.localizedDescription)"
            DiagnosticLog.write("File import failed: \(error.localizedDescription)")
        }
    }
    func remove(_ url: URL) { selectedFiles.removeAll { $0 == url } }
    func removeAll() { selectedFiles.removeAll(); showEditor = false }
    func send(to device: NearbyDevice) {
        guard !selectedFiles.isEmpty else { showSelectionWarning = true; return }
        isSending = true; sendStatus = "正在请求 \(device.alias) 接收…"
        Task {
            do {
                DiagnosticLog.write("Send started: target=\(device.serviceName); files=\(selectedFiles.count).")
                try await BonjourLocalSendSender().send(files: selectedFiles, to: device, local: local)
                await MainActor.run { self.selectedFiles = []; self.sendStatus = "传输完成"; self.isSending = false }
                DiagnosticLog.write("Send completed: target=\(device.serviceName).")
            } catch {
                DiagnosticLog.write("Send failed: target=\(device.serviceName); error=\(error.localizedDescription).")
                await MainActor.run { self.sendStatus = "传输失败：\(error.localizedDescription)"; self.isSending = false }
            }
        }
    }
    func decideIncoming(_ accepted: Bool) { guard let request = incomingTransfer else { return }; receiver.decide(sessionID: request.id, accepted: accepted); incomingTransfer = nil }
}

public struct NearbyDevice: Identifiable, Hashable { public let id: String; public let alias: String; public let deviceType: String; public let serviceName: String; public let serviceType: String; public let serviceDomain: String }
