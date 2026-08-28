import SwiftUI
import UniformTypeIdentifiers

struct TransferView: View {
    @Bindable var model: TransferModel
    @State private var importing = false

    var body: some View {
        NavigationStack {
            List {
                Section("附近设备") {
                    if model.devices.isEmpty { ContentUnavailableView("未发现设备", systemImage: "wifi", description: Text("请确认两台设备在同一局域网并保持应用打开")) }
                    ForEach(model.devices) { device in
                        Button { model.send(to: device) } label: {
                            HStack { Image(systemName: device.platform == "windows" ? "desktopcomputer" : "iphone"); VStack(alignment: .leading) { Text(device.name); Text(device.platform).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "paperplane.fill") }
                        }.disabled(model.selectedFiles.isEmpty || model.isSending)
                    }
                }
                Section("待发送") {
                    ForEach(model.selectedFiles) { Text($0.relativePath) }.onDelete(perform: model.removeFiles)
                    Button("选择文件", systemImage: "plus") { importing = true }
                }
                Section("状态") {
                    Text(model.statusText)
                    if let value = model.progress { ProgressView(value: Double(value.transferredBytes), total: Double(max(1, value.totalBytes))) }
                    if model.isSending { Button("取消发送", role: .destructive) { model.cancelSend() } }
                }
            }
            .navigationTitle("暮色互传")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in if case let .success(urls) = result { model.addFiles(urls) } }
            .sheet(item: $model.pendingRequest, onDismiss: model.dismissPending) { ReceiveRequestSheet(request: $0, accept: model.acceptPending, reject: model.rejectPending) }
            .alert("操作失败", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("好") {} } message: { Text(model.errorMessage ?? "") }
        }
    }
}
