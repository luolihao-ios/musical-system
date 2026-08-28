import Foundation
import MuseTransferCore
import Observation

@MainActor @Observable
final class TransferModel {
    var devices: [NearbyDevice] = []
    var selectedFiles: [OutgoingFile] = []
    var pendingRequest: IncomingTransferRequest?
    var progress: TransferProgress?
    var statusText = "准备就绪"
    var history: [TransferHistoryRecord] = []
    var isSending = false
    var errorMessage: String?
    var manualAddress = ""
    var manualPublicKey = ""
    var receiverPort: UInt16?
    var receiverPublicKey: String { container.receiver.publicKey.base64EncodedString() }

    private let container: AppContainer
    private var discoveryTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?

    init(container: AppContainer) { self.container = container }

    func start() {
        guard discoveryTask == nil else { return }
        let identity = TransferServiceIdentity(id: persistentDeviceID(), name: ProcessInfo.processInfo.hostName, publicKey: container.receiver.publicKey)
        do { try container.receiver.start(identity: identity) } catch { errorMessage = error.localizedDescription }
        Task { try? await Task.sleep(for: .milliseconds(500)); receiverPort = container.receiver.port }
        discoveryTask = Task { for await devices in container.browser.devices() { self.devices = devices } }
        requestTask = Task { for await request in container.receiver.requests() { self.pendingRequest = request } }
        Task { history = (try? await container.history.load()) ?? [] }
        importShareInbox()
    }

    func stop() { container.browser.stop(); container.receiver.stop(); discoveryTask?.cancel(); requestTask?.cancel(); sendTask?.cancel() }
    func addFiles(_ urls: [URL]) { selectedFiles.append(contentsOf: urls.map { OutgoingFile(url: $0) }) }
    func removeFiles(at offsets: IndexSet) { selectedFiles.remove(atOffsets: offsets) }

    func send(to device: NearbyDevice) {
        guard !selectedFiles.isEmpty, !isSending else { return }
        isSending = true; statusText = "等待对方确认…"; let files = selectedFiles
        sendTask = Task {
            let scoped = files.filter { $0.url.startAccessingSecurityScopedResource() }
            defer { scoped.forEach { $0.url.stopAccessingSecurityScopedResource() }; isSending = false }
            do {
                try await container.sender.send(files: files, to: device) { value in Task { @MainActor in self.progress = value; self.statusText = "正在发送 \(value.currentFile)" } }
                statusText = "发送完成"; selectedFiles.removeAll()
                try await record(device: device.name, files: files, direction: .sent, result: .completed)
            } catch is CancellationError { statusText = "已取消"; try? await record(device: device.name, files: files, direction: .sent, result: .cancelled) }
            catch { errorMessage = error.localizedDescription; statusText = "发送失败"; try? await record(device: device.name, files: files, direction: .sent, result: .failed) }
        }
    }

    func cancelSend() { sendTask?.cancel() }
    func sendManual() {
        guard !selectedFiles.isEmpty, !isSending else { return }
        do {
            let endpoint = try TransferEndpoint(manualAddress: manualAddress)
            guard let key = Data(base64Encoded: manualPublicKey), key.count == 65 else { throw TransferWireError.invalidEndpoint }
            let files = selectedFiles; isSending = true; statusText = "等待对方确认…"
            sendTask = Task {
                defer { isSending = false }
                do {
                    try await container.sender.send(files: files, manualEndpoint: endpoint, receiverPublicKey: key) { value in Task { @MainActor in self.progress = value; self.statusText = "正在发送 \(value.currentFile)" } }
                    statusText = "发送完成"; selectedFiles.removeAll()
                } catch { errorMessage = error.localizedDescription; statusText = "发送失败" }
            }
        } catch { errorMessage = "请输入“主机:端口”和接收端显示的 Base64 公钥。" }
    }
    func acceptPending() {
        guard let request = pendingRequest else { return }
        do { try container.receiver.accept(request.id); statusText = "正在接收…"; pendingRequest = nil }
        catch { errorMessage = error.localizedDescription }
    }
    func rejectPending() {
        guard let request = pendingRequest else { return }
        do { try container.receiver.reject(request.id); pendingRequest = nil; statusText = "已拒绝" }
        catch { errorMessage = error.localizedDescription }
    }
    func dismissPending() { rejectPending() }
    func clearHistory() { Task { try? await container.history.clear(); history = [] } }
    func importSelectedIntoMusic() {
        let files = selectedFiles
        Task {
            do { statusText = try await container.musicHandoff.handoff(files: files) ? "已交给暮色音乐" : "没有可导入的音乐或暮色音乐未安装" }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func record(device: String, files: [OutgoingFile], direction: TransferHistoryRecord.Direction, result: TransferHistoryRecord.Result) async throws {
        let total = files.reduce(Int64(0)) { $0 + ((try? FileManager.default.attributesOfItem(atPath: $1.url.path)[.size] as? NSNumber)?.int64Value ?? 0) }
        let value = TransferHistoryRecord(id: UUID(), deviceName: device, date: Date(), fileNames: files.map(\.relativePath), totalBytes: total, direction: direction, result: result)
        try await container.history.append(value); history = try await container.history.load()
    }

    private func persistentDeviceID() -> String {
        let key = "MuseTransferDeviceID"; if let value = UserDefaults.standard.string(forKey: key) { return value }
        let value = UUID().uuidString.lowercased(); UserDefaults.standard.set(value, forKey: key); return value
    }

    private func importShareInbox() {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.luolihao.musetransfer")?.appending(path: "ShareInbox") else { return }
        let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        addFiles(urls)
    }
}
