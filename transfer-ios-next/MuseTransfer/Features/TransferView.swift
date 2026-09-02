import SwiftUI
import UniformTypeIdentifiers

struct TransferView: View {
    @State private var model = TransferViewModel()
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text("附近设备").font(.largeTitle.bold()); Spacer(); Button("刷新", systemImage: "arrow.clockwise") { model.refresh() }.buttonStyle(.borderedProminent).tint(.indigo) }
                Button("选择文件", systemImage: "doc") { model.showImporter = true }.buttonStyle(.bordered).tint(.indigo)
                Text(model.selectedSummary).foregroundStyle(.secondary)
                if model.devices.isEmpty { ContentUnavailableView("暂未发现设备", systemImage: "wifi.exclamationmark", description: Text("请确认设备连接同一 Wi‑Fi 后点击刷新")) }
                ForEach(model.devices) { device in
                    HStack { Image(systemName: device.deviceType == "mobile" ? "iphone" : "desktopcomputer").font(.title2).foregroundStyle(.indigo); VStack(alignment: .leading) { Text(device.alias).font(.headline); Text(device.deviceType).foregroundStyle(.secondary) }; Spacer(); Button("发送") { model.send(to: device) }.buttonStyle(.borderedProminent).tint(.indigo) }
                    .padding().background(.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                }
                Spacer()
            }.padding().navigationTitle("爱乐互传")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { ShareLink(item: DiagnosticLog.fileURL) { Image(systemName: "stethoscope") }.accessibilityLabel("导出诊断日志") } }
        }.fileImporter(isPresented: $model.showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { model.select($0) }
        .alert("接收文件？", isPresented: Binding(get: { model.incomingTransfer != nil }, set: { if !$0 { model.decideIncoming(false) } })) {
            Button("拒绝", role: .destructive) { model.decideIncoming(false) }
            Button("接受") { model.decideIncoming(true) }
        } message: { Text("\(model.incomingTransfer?.sender.alias ?? "设备") 要发送 \(model.incomingTransfer?.files.count ?? 0) 个文件") }
    }
}
