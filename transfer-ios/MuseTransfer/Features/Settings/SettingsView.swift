import SwiftUI

struct SettingsView: View {
    @Bindable var model: TransferModel
    var body: some View {
        NavigationStack { Form { Section("接收") { LabeledContent("保存位置", value: "文件 > 暮色互传 > Received"); LabeledContent("端口", value: model.receiverPort.map(String.init) ?? "正在启动"); Text(model.receiverPublicKey).font(.caption.monospaced()).textSelection(.enabled) }; Section("安全") { Text("每批文件都必须手动确认，传输内容使用端到端会话密钥加密。") }; Section("关于") { LabeledContent("协议", value: "Muse Transfer v2") } }.navigationTitle("设置") }
    }
}
