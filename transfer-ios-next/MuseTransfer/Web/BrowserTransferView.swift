import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import CoreTransferable

@MainActor final class BrowserTransferModel: ObservableObject {
    @Published var address = ""
    @Published var code = ""
    @Published var error = ""
    @Published var upload: WebUpload?
    @Published var offeredFiles: [OfferedBrowserFile] = []
    @Published var pendingFiles: [OfferedBrowserFile] = []
    private var server: BrowserTransferServer?
    func start() {
        address = ""; code = ""; error = ""; upload = nil
        TransferStorage.normalize()
        DiagnosticLog.reset()
        try? FileManager.default.removeItem(at: offeredRoot)
        try? FileManager.default.removeItem(at: pendingRoot)
        try? FileManager.default.createDirectory(at: offeredRoot, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: pendingRoot, withIntermediateDirectories: true)
        offeredFiles = []
        pendingFiles = []
        do {
            if server == nil {
                let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let server = try BrowserTransferServer(root: root, alias: UIDevice.current.name)
                server.onReady = { [weak self] address, code in Task { @MainActor in self?.address = address; self?.code = code } }
                server.onError = { [weak self] error in Task { @MainActor in self?.error = error } }
                server.onUpload = { [weak self] upload in Task { @MainActor in self?.upload = upload } }
                self.server = server
            }
            server?.start(); UIApplication.shared.isIdleTimerDisabled = true
        } catch { self.error = error.localizedDescription }
    }
    func stop() { server?.stop(); try? FileManager.default.removeItem(at: offeredRoot); try? FileManager.default.removeItem(at: pendingRoot); offeredFiles = []; pendingFiles = []; address = ""; code = ""; UIApplication.shared.isIdleTimerDisabled = false }
    func decide(_ accepted: Bool) { if let upload { server?.decide(upload.id, accepted: accepted) } }
    var offeredRoot: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("电脑临时下载", isDirectory: true) }
    var pendingRoot: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("电脑待发布", isDirectory: true) }
    func publishPending() {
        for file in pendingFiles { let target = offeredRoot.appendingPathComponent(file.url.lastPathComponent); try? FileManager.default.moveItem(at: file.url, to: target); offeredFiles.append(OfferedBrowserFile(name: file.name, bytes: file.bytes, url: target)) }
        pendingFiles = []
    }
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
                    Button("复制地址", systemImage: "doc.on.doc") { UIPasteboard.general.string = model.address }
                    Text("访问码：\(model.code)").font(.title.bold())
                }
                Text("请保持此页面打开。切换到后台后服务关闭，返回后显示新的访问码。").foregroundStyle(.secondary)
                Text("文件保存到：文件 › 我的 iPhone › 爱乐互传 › 按日期分类").font(.footnote)
                HStack {
                    Button("添加手机文件供电脑下载") { importing = true }
                    PhotosPicker(selection: $photos, maxSelectionCount: 50, matching: .any(of: [.images, .videos])) { Text("添加媒体") }
                }.buttonStyle(.bordered)
                if !importMessage.isEmpty { Text(importMessage).foregroundStyle(.secondary) }
                if !model.pendingFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("待提供给电脑").font(.headline); Spacer(); Button("提供给电脑下载") { model.publishPending() }.buttonStyle(.borderedProminent) }
                        ForEach(model.pendingFiles) { file in
                            HStack { Image(systemName: "doc").foregroundStyle(.indigo); Text(file.name).lineLimit(1); Spacer(); Button("删除", role: .destructive) { model.pendingFiles.removeAll { $0.id == file.id }; try? FileManager.default.removeItem(at: file.url) }.font(.caption) }
                        }
                    }.padding().background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                }
                if !model.offeredFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("已提供给电脑下载").font(.headline)
                        ForEach(model.offeredFiles) { file in
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
                    let store = try WebFileStore(root: model.pendingRoot)
                for url in try result.get() {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    try FileManager.default.copyItem(at: url, to: temporary)
                    let saved = try store.save(temporary, as: url.lastPathComponent)
                    let savedURL = model.pendingRoot.appendingPathComponent(saved)
                    model.pendingFiles.append(OfferedBrowserFile(name: url.lastPathComponent, bytes: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0), url: savedURL))
                }
                importMessage = "已添加到待提供列表，发布后电脑端才可见"
            } catch { importMessage = error.localizedDescription }
        }
        .onChange(of: photos) { _, items in Task {
            do {
                    let store = try WebFileStore(root: model.pendingRoot)
                for item in items {
                    guard let file = try await item.loadTransferable(type: BrowserPickedMedia.self) else { continue }
                    defer { try? FileManager.default.removeItem(at: file.url) }
                    let name = "媒体-" + UUID().uuidString.prefix(8) + "." + file.url.pathExtension
                    let saved = try store.save(file.url, as: name)
                    let savedURL = model.pendingRoot.appendingPathComponent(saved)
                    model.pendingFiles.append(OfferedBrowserFile(name: name, bytes: Int64((try? file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0), url: savedURL))
                }
                importMessage = "媒体已添加到待提供列表，发布后电脑端才可见"
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

struct OfferedBrowserFile: Identifiable {
    let id = UUID()
    let name: String
    let bytes: Int64
    let url: URL
    var size: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
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
