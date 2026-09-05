import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct TransferView: View {
    @State private var model = TransferViewModel()
    @State private var mediaItems: [PhotosPickerItem] = []
    @State private var textToSend = ""
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("选择").font(.title.bold())
                if model.selectedFiles.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        PhotosPicker(selection: $mediaItems, maxSelectionCount: 50, matching: .any(of: [.images, .videos])) { SelectionTile(title: "媒体", icon: "photo.on.rectangle") }
                        Button { model.showTextEntry = true } label: { SelectionTile(title: "文本", icon: "text.alignleft") }
                        Button { model.addClipboard() } label: { SelectionTile(title: "剪贴板", icon: "clipboard") }
                        Button { model.showImporter = true } label: { SelectionTile(title: "文件", icon: "doc") }
                        Button { model.showFolderImporter = true } label: { SelectionTile(title: "文件夹", icon: "folder") }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("选择").font(.headline); Spacer(); Button("编辑") { model.showEditor = true }.foregroundStyle(.indigo) }
                        Text(model.selectedSummary).foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 12) { ForEach(model.selectedFiles, id: \.self) { url in
                            VStack(spacing: 7) { Image(systemName: thumbnailIcon(url)).font(.title2).foregroundStyle(.indigo).frame(width: 52, height: 52).background(.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 12)); Text(url.lastPathComponent).font(.caption).lineLimit(1).frame(width: 82); Button("移除") { model.remove(url) }.font(.caption2) }.frame(width: 92)
                        } } }
                        Button("添加文件", systemImage: "plus") { model.showImporter = true }.buttonStyle(.bordered).tint(.indigo)
                    }.padding().background(.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                }
                HStack(spacing: 8) {
                    Text("附近设备").font(.title.bold())
                    Button { model.refresh() } label: {
                        Image(systemName: "arrow.clockwise")
                            .symbolEffect(.rotate, options: .repeat(2), value: model.refreshToken)
                    }.buttonStyle(.plain).foregroundStyle(.indigo).accessibilityLabel("刷新附近设备")
                }
                if let status = model.sendStatus { Text(status).foregroundStyle(status == "传输完成" ? .green : .secondary) }
                if model.devices.isEmpty { ContentUnavailableView("暂未发现设备", systemImage: "wifi.exclamationmark", description: Text("请确认设备连接同一 Wi‑Fi 后点击刷新")) }
                ForEach(model.devices) { device in
                    HStack { Image(systemName: device.deviceType == "mobile" ? "iphone" : "desktopcomputer").font(.title2).foregroundStyle(.indigo); VStack(alignment: .leading) { Text(device.alias).font(.headline); Text(device.deviceType).foregroundStyle(.secondary) }; Spacer(); if model.isSending { ProgressView() } }
                    .padding().background(.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 16)).contentShape(RoundedRectangle(cornerRadius: 16)).onTapGesture { model.send(to: device) }
                }
                Spacer()
            }.padding().navigationTitle("爱乐互传")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { ShareLink(item: DiagnosticLog.fileURL) { Image(systemName: "stethoscope") }.accessibilityLabel("导出诊断日志") } }
        }.fileImporter(isPresented: $model.showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { model.select($0) }
        .fileImporter(isPresented: $model.showFolderImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { model.selectFolder($0) }
        .onChange(of: mediaItems) { _, items in Task { await model.selectMedia(items); mediaItems = [] } }
        .sheet(isPresented: Binding(get: { model.incomingTransfer != nil }, set: { if !$0, model.incomingTransfer != nil { model.decideIncoming(false) } })) {
            if let request = model.incomingTransfer { IncomingTransferSheet(request: request, decide: model.decideIncoming) }
        }
        .fullScreenCover(isPresented: Binding(get: { model.isReceiving || model.receiveCompleted }, set: { if !$0 { model.closeReceiveSummary() } })) {
            ReceiveProgressScreen(model: model)
        }
        .alert("未选择文件", isPresented: $model.showSelectionWarning) { Button("关闭", role: .cancel) { } } message: { Text("请至少选择一个文件。") }
        .alert("发送文本", isPresented: $model.showTextEntry) { TextField("输入文本", text: $textToSend, axis: .vertical); Button("取消", role: .cancel) { textToSend = "" }; Button("添加") { model.addText(textToSend); textToSend = "" } } message: { Text("文本会以 .txt 文件发送。") }
        .sheet(isPresented: $model.showEditor) { SelectionEditor(model: model) }
    }

    private func thumbnailIcon(_ url: URL) -> String {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
        if type?.conforms(to: .image) == true { return "photo" }
        if type?.conforms(to: .audio) == true { return "music.note" }
        if type?.conforms(to: .movie) == true { return "film" }
        return "doc"
    }
}

private struct SelectionTile: View {
    let title: String
    let icon: String
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: icon).font(.title2)
            Text(title).font(.headline)
        }
        .foregroundStyle(.indigo)
        .frame(maxWidth: .infinity, minHeight: 82)
        .background(.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ReceiveProgressScreen: View {
    @Bindable var model: TransferViewModel

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(model.receiveCompleted ? "已接收文件" : "正在接收文件")
                    .font(.largeTitle.bold())
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.expectedIncomingFiles, id: \.id) { expected in
                            let saved = model.receivingFiles.first { $0.id == expected.id }
                            ReceiveFileRow(name: expected.fileName, size: saved?.size ?? expected.size,
                                           savedDescription: saved?.savedDescription,
                                           completed: saved != nil)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.receiveCompleted ? "已完成" : "正在接收")
                        .font(.title2.bold())
                    ProgressView(value: totalProgress)
                        .tint(.indigo)
                    HStack {
                        Text("\(model.receivingFiles.count) / \(model.expectedIncomingFiles.count) 个文件")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if model.receiveCompleted {
                            Button("完成", systemImage: "checkmark.circle.fill") { model.closeReceiveSummary() }
                                .buttonStyle(.borderedProminent).tint(.indigo)
                        }
                    }
                }
                .padding()
                .background(.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(!model.receiveCompleted)
    }

    private var totalProgress: Double {
        guard !model.expectedIncomingFiles.isEmpty else { return 0 }
        return Double(model.receivingFiles.count) / Double(model.expectedIncomingFiles.count)
    }
}

private struct ReceiveFileRow: View {
    let name: String
    let size: Int64
    let savedDescription: String?
    let completed: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: fileIcon)
                .font(.title2).foregroundStyle(.indigo)
                .frame(width: 52, height: 52)
                .background(.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 5) {
                Text(name).font(.headline).lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)).font(.subheadline).foregroundStyle(.secondary)
                Text(savedDescription ?? "等待接收…")
                    .font(.subheadline).foregroundStyle(completed ? .green : .secondary)
                ProgressView(value: completed ? 1 : 0)
                    .tint(.indigo)
            }
        }
        .padding()
        .background(.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private var fileIcon: String {
        let extensionName = URL(fileURLWithPath: name).pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "heic", "webp"].contains(extensionName) ? "photo" : "doc"
    }
}

private struct IncomingTransferSheet: View {
    let request: IncomingTransfer
    let decide: (Bool) -> Void
    var body: some View {
        VStack(spacing: 26) {
            Image(systemName: request.sender.deviceType == "mobile" ? "iphone" : "desktopcomputer").font(.system(size: 58)).foregroundStyle(.indigo)
            Text(request.sender.alias).font(.largeTitle.bold())
            Text("想要发送给你 \(request.files.count) 个文件").font(.title3).foregroundStyle(.secondary)
            Text(request.files.values.map(\.fileName).prefix(3).joined(separator: "\n"))
                .multilineTextAlignment(.center).foregroundStyle(.secondary).lineLimit(3)
            HStack(spacing: 18) {
                Button("拒绝", systemImage: "xmark") { decide(false) }.buttonStyle(.borderedProminent).tint(.red)
                Button("接受", systemImage: "checkmark") { decide(true) }.buttonStyle(.borderedProminent).tint(.indigo)
            }
        }.padding(36).presentationDetents([.medium]).interactiveDismissDisabled(false)
    }
}

private struct SelectionEditor: View {
    @Bindable var model: TransferViewModel
    var body: some View {
        NavigationStack {
            List {
                Section { ForEach(model.selectedFiles, id: \.self) { url in
                    HStack { Image(systemName: thumbnailIcon(url)).foregroundStyle(.indigo); VStack(alignment: .leading) { Text(url.lastPathComponent).lineLimit(1); Text(fileSize(url)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button(role: .destructive) { model.remove(url) } label: { Image(systemName: "trash") } }
                }.onDelete { indexSet in for index in indexSet.sorted(by: >) { model.selectedFiles.remove(at: index) } } }
            }.navigationTitle("编辑文件").toolbar { ToolbarItem(placement: .topBarLeading) { Button("全部删除", role: .destructive) { model.removeAll() } }; ToolbarItem(placement: .topBarTrailing) { Button("完成") { model.showEditor = false } } }
        }
    }
    private func thumbnailIcon(_ url: URL) -> String { let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType); if type?.conforms(to: .image) == true { return "photo" }; if type?.conforms(to: .audio) == true { return "music.note" }; return "doc" }
    private func fileSize(_ url: URL) -> String { ByteCountFormatter.string(fromByteCount: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0), countStyle: .file) }
}
