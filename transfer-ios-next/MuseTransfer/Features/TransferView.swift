import SwiftUI
import UniformTypeIdentifiers

struct TransferView: View {
    @State private var model = TransferViewModel()
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text("附近设备").font(.largeTitle.bold()); Spacer(); Button("刷新", systemImage: "arrow.clockwise") { model.refresh() }.buttonStyle(.borderedProminent).tint(.indigo) }
                if model.selectedFiles.isEmpty {
                    Button("选择文件", systemImage: "doc") { model.showImporter = true }.buttonStyle(.bordered).tint(.indigo)
                    Text(model.selectedSummary).foregroundStyle(.secondary)
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
        .sheet(isPresented: Binding(get: { model.incomingTransfer != nil }, set: { if !$0, model.incomingTransfer != nil { model.decideIncoming(false) } })) {
            if let request = model.incomingTransfer { IncomingTransferSheet(request: request, decide: model.decideIncoming) }
        }
        .alert("未选择文件", isPresented: $model.showSelectionWarning) { Button("关闭", role: .cancel) { } } message: { Text("请至少选择一个文件。") }
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
