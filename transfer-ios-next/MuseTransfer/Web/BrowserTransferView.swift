import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import CoreTransferable

@MainActor final class BrowserTransferModel: ObservableObject {
    @Published var address = ""
    @Published var code = ""
    @Published var error = ""
    @Published var upload: WebUpload?
    @Published var outboundFiles: [BrowserOutboundTask] = []
    private var server: BrowserTransferServer?
    func start() {
        address = ""; code = ""; error = ""; upload = nil
        TransferStorage.normalize()
        DiagnosticLog.reset()
        try? FileManager.default.removeItem(at: outboundRoot)
        try? FileManager.default.createDirectory(at: outboundRoot, withIntermediateDirectories: true)
        outboundFiles = []
        do {
            if server == nil {
                let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let server = try BrowserTransferServer(root: root, alias: UIDevice.current.name, outboundRoot: outboundRoot)
                server.onReady = { [weak self] address, code in Task { @MainActor in self?.address = address; self?.code = code } }
                server.onError = { [weak self] error in Task { @MainActor in self?.error = error } }
                server.onUpload = { [weak self] upload in Task { @MainActor in self?.upload = upload } }
                self.server = server
            }
            server?.start(); UIApplication.shared.isIdleTimerDisabled = true
        } catch { self.error = error.localizedDescription }
    }
    func stop() { server?.stop(); try? FileManager.default.removeItem(at: outboundRoot); outboundFiles = []; address = ""; code = ""; UIApplication.shared.isIdleTimerDisabled = false }
    func decide(_ accepted: Bool) { if let upload { server?.decide(upload.id, accepted: accepted) } }
    var outboundRoot: URL { FileManager.default.temporaryDirectory.appendingPathComponent("AiYueBrowserOutbound", isDirectory: true) }
}

struct BrowserTransferView: View {
    @StateObject private var model = BrowserTransferModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var importing = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var importMessage = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("电脑和手机连接同一个 Wi-Fi，在电脑浏览器打开下面的地址。").font(.title3)
                if model.address.isEmpty { Text(model.error.isEmpty ? "正在启动网页服务…" : model.error) }
                else {
                    Text(model.address).font(.title2.monospaced()).textSelection(.enabled)
                    Text("访问码：\(model.code)").font(.title.bold())
                }
                Text("不要关闭此应用。请保持此页面打开，切换到后台后服务会关闭。").foregroundStyle(.secondary)
                Text("文件保存到：文件 › 我的 iPhone › 爱乐互传 › 按日期分类").font(.footnote)
                HStack {
                    Button("添加手机文件供电脑下载") { importing = true }
                    PhotosPicker(selection: $photos, maxSelectionCount: 50, matching: .any(of: [.images, .videos])) { Text("添加媒体") }
                }.buttonStyle(.bordered)
                if !importMessage.isEmpty { Text(importMessage).foregroundStyle(.secondary) }
                if !model.outboundFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("发送给电脑").font(.headline)
                        ForEach(model.outboundFiles) { file in
                            HStack {
                                Image(systemName: "doc").foregroundStyle(.indigo)
                                VStack(alignment: .leading) { Text(file.name).lineLimit(1); Text(file.size).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                            }
                        }
                    }.padding().background(.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                }
                if let batch = model.upload {
                    Divider()
                    Text("接收文件").font(.title2.bold())
                    VStack(alignment: .leading, spacing: 16) {
                        Text(batch.state == "waiting" ? "电脑请求发送 \(batch.files.count) 个文件" : batch.state == "completed" ? "接收完成" : "传输状态：\(stateLabel(batch.state))").font(.headline)
                        ForEach(batch.files) { file in
                            VStack(alignment: .leading) {
                                Text(file.name).lineLimit(2)
                                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)).font(.caption)
                                if let path = batch.saved[file.id] {
                                    Text("已保存到文件 › 爱乐互传 / \(path)").font(.caption).foregroundStyle(.green)
                                    if path.lowercased().hasSuffix(".aiyuepack") { ShareLink("导入爱乐之城", item: sharedRoot.appendingPathComponent(path)) }
                                }
                                else { Text((batch.progress[file.id] ?? 0) > 0 ? "正在接收…" : "等待接收").font(.caption).foregroundStyle(.secondary) }
                                ProgressView(value: batch.saved[file.id] != nil ? 1 : min(0.99, Double(batch.progress[file.id] ?? 0) / Double(max(1, file.size))))
                            }
                        }
                        if batch.state == "waiting" { HStack { Button("拒绝", role: .destructive) { model.decide(false) }; Spacer(); Button("接受") { model.decide(true) }.buttonStyle(.borderedProminent) } }
                        if ["completed", "rejected", "expired", "cancelled"].contains(batch.state) { Button("完成") { model.upload = nil } }
                    }.padding().background(.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                }
                Button("重新开启服务") { model.start() }
            }.padding()
        }.navigationTitle("浏览器传文件").tint(.indigo)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            do {
                    let store = try WebFileStore(root: model.outboundRoot)
                for url in try result.get() {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    try FileManager.default.copyItem(at: url, to: temporary)
                    let saved = try store.save(temporary, as: url.lastPathComponent)
                    let savedURL = model.outboundRoot.appendingPathComponent(saved)
                    model.outboundFiles.append(BrowserOutboundTask(name: url.lastPathComponent, bytes: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0), url: savedURL.path))
                }
                importMessage = "已加入发送队列，电脑浏览器会自动下载"
            } catch { importMessage = error.localizedDescription }
        }
        .onChange(of: photos) { _, items in Task {
            do {
                    let store = try WebFileStore(root: model.outboundRoot)
                for item in items {
                    guard let file = try await item.loadTransferable(type: BrowserPickedMedia.self) else { continue }
                    defer { try? FileManager.default.removeItem(at: file.url) }
                    let name = "媒体-" + UUID().uuidString.prefix(8) + "." + file.url.pathExtension
                    let saved = try store.save(file.url, as: name)
                    let savedURL = model.outboundRoot.appendingPathComponent(saved)
                    model.outboundFiles.append(BrowserOutboundTask(name: name, bytes: Int64((try? file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0), url: savedURL.path))
                }
                importMessage = "媒体已加入发送队列，电脑浏览器会自动下载"
            } catch { importMessage = error.localizedDescription }
            photos = []
        } }
        .onAppear { model.start() }.onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.start() } else if phase == .background { model.stop() } }
    }
    private var sharedRoot: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private func stateLabel(_ value: String) -> String {
        ["accepted": "正在接收", "rejected": "已拒绝", "cancelled": "已取消", "expired": "等待超时"][value] ?? value
    }
}

struct BrowserOutboundTask: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let bytes: Int64
    let url: String
    var size: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    init(id: String = UUID().uuidString, name: String, bytes: Int64, url: String) {
        self.id = id; self.name = name; self.bytes = bytes; self.url = url
    }
}

struct BrowserPickedMedia: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .data) { received in
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: target)
            return BrowserPickedMedia(url: target)
        }
    }
}
