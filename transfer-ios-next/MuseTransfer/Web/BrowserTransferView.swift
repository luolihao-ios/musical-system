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
    @Published var outboundProgress: [String: Double] = [:]
    @Published var outboundCompleted = false
    private var server: BrowserTransferServer?
    func start() {
        #if DEBUG
        if let page = Self.storeCapturePage { loadStoreCapture(page); return }
        #endif
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
                server.onOutboundUpdate = { [weak self] id, progress, state in Task { @MainActor in self?.outboundProgress[id] = progress; if state == "completed", let self { self.outboundCompleted = self.outboundFiles.allSatisfy { (self.outboundProgress[$0.id] ?? 0) >= 1 } } } }
                self.server = server
            }
            server?.start(); UIApplication.shared.isIdleTimerDisabled = true
        } catch { self.error = error.localizedDescription }
    }
    func stop() { server?.stop(); try? FileManager.default.removeItem(at: outboundRoot); outboundFiles = []; address = ""; code = ""; UIApplication.shared.isIdleTimerDisabled = false }
    func decide(_ accepted: Bool) { if let upload { server?.decide(upload.id, accepted: accepted) } }
    func publishOutbound() { outboundCompleted = false; outboundProgress = [:]; server?.publishOutbound() }
    func clearOutbound() { outboundFiles = []; outboundProgress = [:]; outboundCompleted = false; server?.clearOutbound() }
    var outboundRoot: URL { FileManager.default.temporaryDirectory.appendingPathComponent("AiYueBrowserOutbound", isDirectory: true) }

    #if DEBUG
    static var storeCapturePage: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--file-send-store-page"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private func loadStoreCapture(_ page: String) {
        address = "http://192.168.1.23:8080"
        code = "826451"
        let files = [WebUploadFile(id: "photo", name: "旅行照片.zip", size: 48_200_000),
                     WebUploadFile(id: "notes", name: "会议记录.pdf", size: 2_400_000),
                     WebUploadFile(id: "audio", name: "我的音乐.mp3", size: 7_800_000)]
        if page == "receive" || page == "completed" {
            var batch = WebUpload(id: "store-demo", files: files, folder: "2026-10-26")
            batch.state = page == "completed" ? "completed" : "accepted"
            for file in files {
                batch.progress[file.id] = page == "completed" ? file.size : file.size / 2
                if page == "completed" { batch.saved[file.id] = "2026-10-26/" + file.name }
            }
            upload = batch
        } else if page == "send" || page == "edit" {
            outboundFiles = files.map { BrowserOutboundTask(id: $0.id, name: $0.name, bytes: $0.size, url: "/tmp/" + $0.name) }
        }
    }
    #endif
}

struct BrowserTransferView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case receive = "接收"
        case send = "发送"
        var id: String { rawValue }
        var localizedTitle: String { NSLocalizedString(rawValue, comment: "Transfer direction tab") }
    }
    @StateObject private var model = BrowserTransferModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var importing = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var importMessage = ""
    @State private var tab: Tab = .receive
    @State private var editingOutbound = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("电脑和手机连接同一个 Wi-Fi，在电脑浏览器打开下面的地址。").font(.title3)
                if model.address.isEmpty { Text(model.error.isEmpty ? String(localized: "正在启动网页服务…") : model.error) }
                else {
                    Text(model.address).font(.title2.monospaced()).textSelection(.enabled)
                        .lineLimit(2).minimumScaleFactor(0.7).accessibilityIdentifier("transfer.address")
                    Text(String(format: String(localized: "访问码：%@"), model.code)).font(.title.bold())
                }
                Text("不要关闭此应用。请保持此页面打开，切换到后台后服务会关闭。").foregroundStyle(.secondary)
                Text("文件保存到：文件 › 我的 iPhone › file send › 按日期分类").font(.footnote)
                Picker("传输方向", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.localizedTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                if tab == .send {
                    ViewThatFits(in: .horizontal) {
                        HStack { selectionActions }
                        VStack(alignment: .leading) { selectionActions }
                    }.buttonStyle(.bordered)
                    if !importMessage.isEmpty { Text(importMessage).foregroundStyle(.secondary) }
                    if !model.outboundFiles.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text("发送给电脑").font(.headline); Spacer(); Button(editingOutbound ? "完成" : "编辑") { editingOutbound.toggle() }.accessibilityIdentifier("transfer.edit") }
                            ForEach(model.outboundFiles) { file in
                                HStack {
                                    Image(systemName: "doc").foregroundStyle(.indigo)
                                    VStack(alignment: .leading) { Text(file.name).lineLimit(1); Text(file.size).font(.caption).foregroundStyle(.secondary); ProgressView(value: model.outboundProgress[file.id] ?? file.progress) }
                                    Spacer()
                                    if editingOutbound { Button("删除", role: .destructive) { model.outboundFiles.removeAll { $0.id == file.id }; try? FileManager.default.removeItem(atPath: file.url) }.font(.caption) }
                                }
                            }
                        }
                        Button(model.outboundCompleted ? "完成" : "发送给电脑") { model.outboundCompleted ? model.clearOutbound() : model.publishOutbound() }.buttonStyle(.borderedProminent).accessibilityIdentifier("transfer.send")
                    .padding().background(.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                if let batch = model.upload {
                    if tab == .receive {
                        Divider()
                        Text("接收文件").font(.title2.bold())
                        VStack(alignment: .leading, spacing: 16) {
                        Text(batch.state == "waiting" ? String(format: String(localized: "电脑请求发送 %lld 个文件"), batch.files.count) : batch.state == "completed" ? String(localized: "接收完成") : String(localized: "传输状态：") + stateLabel(batch.state)).font(.headline)
                        ForEach(batch.files) { file in
                            VStack(alignment: .leading) {
                                Text(file.name).lineLimit(2)
                                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)).font(.caption)
                                if let path = batch.saved[file.id] {
                                    Text(String(format: String(localized: "已保存到文件 › file send / %@"), path)).font(.caption).foregroundStyle(.green)
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
                }
                Button("重新开启服务") { model.start() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: 1_160, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .accessibilityIdentifier("transfer.content")
        .navigationTitle("浏览器传文件").tint(.indigo)
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
                    model.outboundFiles.append(BrowserOutboundTask(id: url.lastPathComponent, name: url.lastPathComponent, bytes: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0), url: savedURL.path))
                }
                importMessage = String(localized: "已加入发送队列，电脑浏览器会自动下载")
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
                    model.outboundFiles.append(BrowserOutboundTask(id: name, name: name, bytes: Int64((try? file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0), url: savedURL.path))
                }
                importMessage = String(localized: "媒体已加入发送队列，电脑浏览器会自动下载")
            } catch { importMessage = error.localizedDescription }
            photos = []
        } }
        .onAppear {
            #if DEBUG
            if let page = BrowserTransferModel.storeCapturePage { tab = ["send", "edit"].contains(page) ? .send : .receive; editingOutbound = page == "edit" }
            #endif
            model.start()
        }.onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.start() } else if phase == .background { model.stop() } }
    }
    @ViewBuilder private var selectionActions: some View {
        Button("添加手机文件发送给电脑") { importing = true }
            .accessibilityIdentifier("transfer.addFiles")
        PhotosPicker(selection: $photos, maxSelectionCount: 50, matching: .any(of: [.images, .videos])) { Text("添加媒体") }
    }
    private var sharedRoot: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private func stateLabel(_ value: String) -> String {
        ["accepted": String(localized: "正在接收"), "rejected": String(localized: "已拒绝"), "cancelled": String(localized: "已取消"), "expired": String(localized: "等待超时")][value] ?? value
    }
}

struct BrowserOutboundTask: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let bytes: Int64
    let url: String
    let state: String
    let progress: Double
    var size: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    init(id: String = UUID().uuidString, name: String, bytes: Int64, url: String, state: String = "waiting", progress: Double = 0) {
        self.id = id; self.name = name; self.bytes = bytes; self.url = url; self.state = state; self.progress = progress
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
