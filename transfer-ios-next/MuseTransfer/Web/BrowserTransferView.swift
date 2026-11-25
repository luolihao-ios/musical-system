import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import CoreTransferable
import CoreImage.CIFilterBuiltins

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

    private static let qrContext = CIContext()
    private static let importableMusicExtensions: Set<String> = ["aiyuepack", "mp3", "m4a", "flac", "wav", "aiff", "aac", "alac"]

    @StateObject private var model = BrowserTransferModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    @State private var importing = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var importMessage = ""
    @State private var tab: Tab = .receive
    @State private var editingOutbound = false
    @State private var copiedAddress = false
    @State private var copiedCode = false
    @State private var showQRSheet = false

    private var pageBackground: Color {
        colorScheme == .dark
            ? Color(uiColor: .systemGroupedBackground)
            : Color(red: 0.965, green: 0.957, blue: 1.0)
    }

    private var cardBackground: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    private var saveLocationText: String {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return String(localized: "文件保存到：文件 › 我的 iPad › file send › 按日期分类")
        }
        return String(localized: "文件保存到：文件 › 我的 iPhone › file send › 按日期分类")
    }

    var body: some View {
        ScrollView {
            Group {
                if horizontalSizeClass == .regular {
                    HStack(alignment: .top, spacing: 24) {
                        connectionCard
                            .frame(minWidth: 320, maxWidth: 400)
                        transferWorkspace
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        connectionCard
                        transferWorkspace
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: 1_160, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(pageBackground.ignoresSafeArea())
        .accessibilityIdentifier("transfer.content")
        .navigationTitle("浏览器传文件")
        .tint(.indigo)
        .sheet(isPresented: $showQRSheet) { qrPreviewSheet }
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
                    model.outboundFiles.append(BrowserOutboundTask(
                        id: url.lastPathComponent,
                        name: url.lastPathComponent,
                        bytes: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0),
                        url: savedURL.path
                    ))
                }
                importMessage = String(localized: "已加入待发列表，点击下方“发送给电脑”开始传输")
            } catch { importMessage = error.localizedDescription }
        }
        .onChange(of: photos) { _, items in
            Task {
                do {
                    let store = try WebFileStore(root: model.outboundRoot)
                    for item in items {
                        guard let file = try await item.loadTransferable(type: BrowserPickedMedia.self) else { continue }
                        defer { try? FileManager.default.removeItem(at: file.url) }
                        let name = "媒体-" + UUID().uuidString.prefix(8) + "." + file.url.pathExtension
                        let saved = try store.save(file.url, as: name)
                        let savedURL = model.outboundRoot.appendingPathComponent(saved)
                        model.outboundFiles.append(BrowserOutboundTask(
                            id: name,
                            name: name,
                            bytes: Int64((try? file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0),
                            url: savedURL.path
                        ))
                    }
                    importMessage = String(localized: "媒体已加入待发列表，点击下方“发送给电脑”开始传输")
                } catch { importMessage = error.localizedDescription }
                photos = []
            }
        }
        .onAppear {
            #if DEBUG
            if let page = BrowserTransferModel.storeCapturePage {
                tab = ["send", "edit"].contains(page) ? .send : .receive
                editingOutbound = page == "edit"
            }
            #endif
            model.start()
        }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.start() } else if phase == .background { model.stop() }
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 9, height: 9)
                Text(statusHeaderTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(model.error.isEmpty ? Color.primary : Color.red)
                Spacer(minLength: 0)
                Button {
                    model.start()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.indigo)
                        .frame(width: 34, height: 34)
                        .background(.indigo.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("重新开启服务")
            }

            if !model.address.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("在电脑浏览器打开")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .center, spacing: 10) {
                        Text(model.address)
                            .font(.headline.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                            .accessibilityIdentifier("transfer.address")
                        Spacer(minLength: 0)
                        Button {
                            UIPasteboard.general.string = model.address
                            copiedAddress = true
                            Task {
                                try? await Task.sleep(for: .seconds(1.5))
                                copiedAddress = false
                            }
                        } label: {
                            Label(
                                copiedAddress ? String(localized: "已复制") : String(localized: "复制地址"),
                                systemImage: copiedAddress ? "checkmark" : "doc.on.doc"
                            )
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.indigo.opacity(0.12), in: Capsule())
                            .foregroundStyle(.indigo)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack(alignment: .center, spacing: 14) {
                    Button {
                        UIPasteboard.general.string = model.code
                        copiedCode = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            copiedCode = false
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("访问码")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                if copiedCode {
                                    Text("已复制")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.green)
                                }
                            }
                            Text(formattedCode(model.code))
                                .font(.system(size: 30, weight: .bold, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(format: String(localized: "访问码：%@"), model.code))

                    if let qr = qrCodeImage(for: model.address) {
                        Button {
                            showQRSheet = true
                        } label: {
                            Image(uiImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 68, height: 68)
                                .padding(6)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.indigo.opacity(0.18), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("扫码打开")
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Label("不要关闭此应用。请保持此页面打开，切换到后台后服务会关闭。", systemImage: "iphone.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(saveLocationText, systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.indigo.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.05), radius: 14, y: 6)
    }

    private var transferWorkspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("传输方向", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.localizedTitle).tag($0) }
            }
            .pickerStyle(.segmented)

            if tab == .receive {
                receiveSection
            } else {
                sendSection
            }
        }
    }

    @ViewBuilder
    private var receiveSection: some View {
        if let batch = model.upload {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 10) {
                    Text("接收文件")
                        .font(.title3.bold())
                    Spacer(minLength: 0)
                    Text(batchStatusTitle(batch))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(batchStatusColor(batch).opacity(0.14), in: Capsule())
                        .foregroundStyle(batchStatusColor(batch))
                }

                ForEach(batch.files) { file in
                    let savedPath = batch.saved[file.id]
                    let fraction = savedPath != nil ? 1.0 : min(0.99, Double(batch.progress[file.id] ?? 0) / Double(max(1, file.size)))
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: iconName(for: file.name))
                            .font(.headline)
                            .foregroundStyle(.indigo)
                            .frame(width: 40, height: 40)
                            .background(.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                        VStack(alignment: .leading, spacing: 5) {
                            Text(file.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)

                            HStack {
                                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                Spacer(minLength: 0)
                                Text("\(Int((fraction * 100).rounded()))%")
                                    .monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if let path = savedPath {
                                Text(String(format: String(localized: "已保存到文件 › file send / %@"), path))
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                if canImportToMusic(file.name) {
                                    ShareLink(item: sharedRoot.appendingPathComponent(path)) {
                                        Label("导入爱乐之城", systemImage: "music.note")
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.indigo.opacity(0.12), in: Capsule())
                                            .foregroundStyle(.indigo)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 2)
                                }
                            } else {
                                Text((batch.progress[file.id] ?? 0) > 0 ? "正在接收…" : "等待接收")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            ProgressView(value: fraction)
                                .tint(savedPath != nil ? .green : .indigo)
                        }
                    }
                    .padding(12)
                    .background(Color.indigo.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if batch.state == "waiting" {
                    HStack(spacing: 12) {
                        Button("拒绝", role: .destructive) { model.decide(false) }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                        Button("接受") { model.decide(true) }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                    }
                } else if ["completed", "rejected", "expired", "cancelled"].contains(batch.state) {
                    Button {
                        model.upload = nil
                    } label: {
                        Text("完成")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(18)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.indigo.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.05), radius: 14, y: 6)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.title2)
                        .foregroundStyle(.indigo)
                        .frame(width: 44, height: 44)
                        .background(.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("等待电脑发送文件")
                            .font(.headline)
                        Text("同一 Wi-Fi 下在电脑浏览器打开上方地址")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    stepRow(number: "1", text: String(localized: "同一 Wi-Fi 下在电脑浏览器打开上方地址"))
                    stepRow(number: "2", text: String(localized: "输入 6 位访问码即可建立连接"))
                    stepRow(number: "3", text: String(localized: "拖入文件或文件夹即可高速接收"))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.indigo.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.05), radius: 14, y: 6)
        }
    }

    @ViewBuilder
    private var sendSection: some View {
        HStack(spacing: 12) {
            Button {
                importing = true
            } label: {
                selectionCardLabel(
                    title: String(localized: "选择文件"),
                    subtitle: String(localized: "音乐、文档、压缩包"),
                    icon: "folder.badge.plus"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("transfer.addFiles")

            PhotosPicker(selection: $photos, maxSelectionCount: 50, matching: .any(of: [.images, .videos])) {
                selectionCardLabel(
                    title: String(localized: "照片与视频"),
                    subtitle: String(localized: "最多一次选 50 项"),
                    icon: "photo.on.rectangle.angled"
                )
            }
            .buttonStyle(.plain)
        }

        if !importMessage.isEmpty {
            Label(importMessage, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.indigo)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }

        if model.outboundFiles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("选择手机文件发送到电脑", systemImage: "paperplane")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("添加文件后点击发送，电脑浏览器会自动开始接收")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.indigo.opacity(0.12), lineWidth: 1)
            )
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("发送给电脑")
                        .font(.headline)
                    Text("\(model.outboundFiles.count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.indigo.opacity(0.12), in: Capsule())
                        .foregroundStyle(.indigo)
                    Spacer(minLength: 0)
                    Button(editingOutbound ? String(localized: "完成") : String(localized: "编辑")) {
                        editingOutbound.toggle()
                    }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("transfer.edit")
                }

                ForEach(model.outboundFiles) { file in
                    let fraction = model.outboundProgress[file.id] ?? file.progress
                    HStack(spacing: 12) {
                        Image(systemName: iconName(for: file.name))
                            .font(.headline)
                            .foregroundStyle(.indigo)
                            .frame(width: 38, height: 38)
                            .background(.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            HStack {
                                Text(file.size)
                                Spacer(minLength: 0)
                                Text("\(Int((min(max(fraction, 0), 1) * 100).rounded()))%")
                                    .monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            ProgressView(value: fraction)
                                .tint(fraction >= 1 ? .green : .indigo)
                        }

                        if editingOutbound {
                            Button(role: .destructive) {
                                model.outboundFiles.removeAll { $0.id == file.id }
                                try? FileManager.default.removeItem(atPath: file.url)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.subheadline)
                                    .padding(8)
                                    .background(Color.red.opacity(0.12), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("删除")
                        }
                    }
                    .padding(10)
                    .background(Color.indigo.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button {
                    if model.outboundCompleted {
                        model.clearOutbound()
                    } else {
                        model.publishOutbound()
                    }
                } label: {
                    Text(model.outboundCompleted ? "完成" : "发送给电脑")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("transfer.send")
            }
            .padding(18)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.indigo.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.05), radius: 14, y: 6)
        }
    }

    private func selectionCardLabel(title: String, subtitle: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.indigo)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.indigo.opacity(0.14), lineWidth: 1)
        )
    }

    private func stepRow(number: String, text: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.indigo)
                .frame(width: 22, height: 22)
                .background(.indigo.opacity(0.12), in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var qrPreviewSheet: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if let qr = qrCodeImage(for: model.address) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                }
                Text(model.address)
                    .font(.headline.monospaced())
                    .textSelection(.enabled)
                Text(String(format: String(localized: "访问码：%@"), formattedCode(model.code)))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(.indigo)
            }
            .padding(24)
            .navigationTitle("扫码打开")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { showQRSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var statusDotColor: Color {
        if !model.error.isEmpty { return .red }
        return model.address.isEmpty ? .orange : .green
    }

    private var statusHeaderTitle: String {
        if !model.error.isEmpty { return model.error }
        return model.address.isEmpty ? String(localized: "正在启动网页服务…") : String(localized: "网页服务运行中")
    }

    private func batchStatusTitle(_ batch: WebUpload) -> String {
        if batch.state == "waiting" {
            return String(format: String(localized: "电脑请求发送 %lld 个文件"), batch.files.count)
        }
        if batch.state == "completed" {
            return String(localized: "接收完成")
        }
        return stateLabel(batch.state)
    }

    private func batchStatusColor(_ batch: WebUpload) -> Color {
        switch batch.state {
        case "completed": return .green
        case "rejected", "cancelled", "expired": return .red
        default: return .indigo
        }
    }

    private func formattedCode(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 6 else { return trimmed }
        let mid = trimmed.index(trimmed.startIndex, offsetBy: 3)
        return "\(trimmed[..<mid]) \(trimmed[mid...])"
    }

    private func qrCodeImage(for string: String) -> UIImage? {
        guard !string.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = Self.qrContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func canImportToMusic(_ fileName: String) -> Bool {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        return Self.importableMusicExtensions.contains(ext)
    }

    private func iconName(for fileName: String) -> String {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        if ["mp3", "m4a", "flac", "wav", "aiff", "aac", "alac", "aiyuepack"].contains(ext) { return "music.note" }
        if ["jpg", "jpeg", "png", "gif", "heic", "webp"].contains(ext) { return "photo" }
        if ["mp4", "mov", "m4v", "mkv", "avi", "webm"].contains(ext) { return "film" }
        if ["zip", "rar", "7z", "tar", "gz"].contains(ext) { return "doc.zipper" }
        if ext == "pdf" { return "doc.richtext" }
        return "doc"
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
