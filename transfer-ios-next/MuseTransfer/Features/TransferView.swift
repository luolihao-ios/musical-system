import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct TransferView: View {
    @State private var model = TransferViewModel()
    @State private var mediaItems: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            BrowserTransferView()
                .navigationTitle("file send")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            ShareLink(item: DiagnosticLog.fileURL) {
                                Label("导出诊断日志", systemImage: "stethoscope")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("更多选项")
                    }
                }
        }
        .fileImporter(isPresented: $model.showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { model.select($0) }
        .fileImporter(isPresented: $model.showFolderImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { model.selectFolder($0) }
        .onChange(of: mediaItems) { _, items in Task { await model.selectMedia(items); mediaItems = [] } }
        .sheet(isPresented: Binding(get: { model.incomingTransfer != nil }, set: { if !$0, model.incomingTransfer != nil { model.decideIncoming(false) } })) {
            if let request = model.incomingTransfer { IncomingTransferSheet(request: request, decide: model.decideIncoming) }
        }
        .fullScreenCover(isPresented: Binding(get: { model.isReceiving || model.receiveCompleted }, set: { if !$0 { model.closeReceiveSummary() } })) {
            ReceiveProgressScreen(model: model)
        }
        .alert("未选择文件", isPresented: $model.showSelectionWarning) { Button("关闭", role: .cancel) { } } message: { Text("请至少选择一个文件。") }
        .sheet(isPresented: $model.showEditor) { SelectionEditor(model: model) }
    }
}

private struct ReceiveProgressScreen: View {
    private static let importableMusicExtensions: Set<String> = ["aiyuepack", "mp3", "m4a", "flac", "wav", "aiff", "aac", "alac"]
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
                            if let saved, Self.importableMusicExtensions.contains(saved.url.pathExtension.lowercased()) {
                                ShareLink(item: saved.url) {
                                    Label("导入爱乐之城", systemImage: "music.note")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(Color.indigo.opacity(0.12), in: Capsule())
                                        .foregroundStyle(.indigo)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.receiveCompleted ? "已完成" : "正在接收")
                        .font(.title2.bold())
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
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        if ["mp3", "m4a", "flac", "wav", "aiff", "aac", "alac", "aiyuepack"].contains(ext) { return "music.note" }
        if ["jpg", "jpeg", "png", "gif", "heic", "webp"].contains(ext) { return "photo" }
        if ["mp4", "mov", "m4v", "mkv", "avi", "webm"].contains(ext) { return "film" }
        if ["zip", "rar", "7z", "tar", "gz"].contains(ext) { return "doc.zipper" }
        if ext == "pdf" { return "doc.richtext" }
        return "doc"
    }
}

private struct IncomingTransferSheet: View {
    let request: IncomingTransfer
    let decide: (Bool) -> Void
    var body: some View {
        VStack(spacing: 26) {
            Image(systemName: request.sender.deviceType == "mobile" ? "iphone" : "desktopcomputer").font(.system(size: 58)).foregroundStyle(.indigo)
            Text(request.sender.alias).font(.largeTitle.bold())
            Text(String(format: String(localized: "想要发送给你 %lld 个文件"), request.files.count)).font(.title3).foregroundStyle(.secondary)
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
