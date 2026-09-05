import Foundation
import SwiftUI
import Observation
import UIKit
import PhotosUI

@Observable final class TransferViewModel {
    var devices: [NearbyDevice] = []
    var selectedFiles: [URL] = []
    var showImporter = false
    var showFolderImporter = false
    var showEditor = false
    var showTextEntry = false
    var refreshToken = 0
    var incomingTransfer: IncomingTransfer?
    var showSelectionWarning = false
    var isSending = false
    var sendStatus: String?
    var receivingFiles: [ReceivedTransferFile] = []
    var expectedIncomingFiles: [FileMetadata] = []
    var isReceiving = false
    var receiveCompleted = false
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
        receiver.onFileReceived = { [weak self] file in Task { @MainActor in self?.recordReceived(file) } }
        do { try receiver.start() } catch { DiagnosticLog.write("iOS receiver start failed: \(error.localizedDescription)") }
        browser.onDevicesChanged = { [weak self] devices in Task { @MainActor in self?.devices = devices } }
        browser.start()
    }
    // Restarting NWListener to refresh Bonjour races with the old TCP socket being
    // released. It caused address-in-use failures and made a previously working
    // iOS advertisement disappear. Refreshing the browser is sufficient here.
    func refresh() { DiagnosticLog.write("User requested discovery refresh."); refreshToken += 1; browser.stop(); browser.start() }
    func select(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result else { return }
        let outgoing = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("爱乐互传/待发送", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outgoing, withIntermediateDirectories: true)
            selectedFiles = try urls.map { source in
                guard source.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
                defer { source.stopAccessingSecurityScopedResource() }
                let batch = outgoing.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: batch, withIntermediateDirectories: true)
                let target = batch.appendingPathComponent(source.lastPathComponent)
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
    func addText(_ value: String) {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let folder = try outgoingBatch()
            let target = folder.appendingPathComponent("文本-\(UUID().uuidString.prefix(8)).txt")
            try value.write(to: target, atomically: true, encoding: .utf8)
            selectedFiles = [target]
        } catch { sendStatus = "无法创建文本：\(error.localizedDescription)" }
    }
    func addClipboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { sendStatus = "剪贴板中没有文本"; return }
        addText(text)
    }
    func selectMedia(_ items: [PhotosPickerItem]) async {
        do {
            let folder = try outgoingBatch()
            var files: [URL] = []
            for item in items {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let type = item.supportedContentTypes.first
                let extensionName = type?.preferredFilenameExtension ?? "bin"
                let target = folder.appendingPathComponent("媒体-\(UUID().uuidString.prefix(8)).\(extensionName)")
                try data.write(to: target, options: .atomic)
                files.append(target)
            }
            selectedFiles = files
            if files.isEmpty { sendStatus = "没有读取到可发送的媒体" }
        } catch { sendStatus = "无法读取媒体：\(error.localizedDescription)" }
    }
    func selectFolder(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let source = urls.first else { return }
        guard source.startAccessingSecurityScopedResource() else { sendStatus = "无法读取所选文件夹"; return }
        defer { source.stopAccessingSecurityScopedResource() }
        do {
            let folder = try outgoingBatch()
            let copied = folder.appendingPathComponent(source.lastPathComponent, isDirectory: true)
            try FileManager.default.copyItem(at: source, to: copied)
            let files = (FileManager.default.enumerator(at: copied, includingPropertiesForKeys: [.isRegularFileKey])?.allObjects as? [URL] ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            selectedFiles = files
            if files.isEmpty { sendStatus = "所选文件夹中没有可发送的文件" }
        } catch { sendStatus = "无法读取文件夹：\(error.localizedDescription)" }
    }
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
    func decideIncoming(_ accepted: Bool) {
        guard let request = incomingTransfer else { return }
        if accepted {
            expectedIncomingFiles = request.files.values.sorted { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }
            receivingFiles = []
            receiveCompleted = false
            isReceiving = true
        }
        receiver.decide(sessionID: request.id, accepted: accepted)
        incomingTransfer = nil
    }

    func closeReceiveSummary() {
        isReceiving = false
        receiveCompleted = false
        expectedIncomingFiles = []
        receivingFiles = []
    }

    private func recordReceived(_ file: ReceivedTransferFile) {
        receivingFiles.removeAll { $0.id == file.id }
        receivingFiles.append(file)
        if !expectedIncomingFiles.isEmpty && receivingFiles.count == expectedIncomingFiles.count {
            receiveCompleted = true
            isReceiving = false
            sendStatus = "接收完成"
        }
    }

    private func outgoingBatch() throws -> URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("爱乐互传/待发送", isDirectory: true)
        let batch = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: batch, withIntermediateDirectories: true)
        return batch
    }
}

public struct NearbyDevice: Identifiable, Hashable { public let id: String; public let alias: String; public let deviceType: String; public let serviceName: String; public let serviceType: String; public let serviceDomain: String }
