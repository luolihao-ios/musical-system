import SwiftUI

struct ReceiveRequestSheet: View {
    let request: IncomingTransferRequest
    let accept: () -> Void
    let reject: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 52)).foregroundStyle(.purple)
                Text("接收来自 \(request.senderName) 的文件？").font(.title2.bold()).multilineTextAlignment(.center)
                Text("\(request.fileCount) 个文件 · \(ByteCountFormatter.string(fromByteCount: request.totalBytes, countStyle: .file))")
                Text("核对码  \(request.verificationCode)").font(.title3.monospacedDigit()).padding().background(.thinMaterial, in: .rect(cornerRadius: 12))
                List(request.manifest.items, id: \.id) { Text($0.relativePath).lineLimit(2) }
                HStack { Button("拒绝", role: .destructive, action: reject).buttonStyle(.bordered); Button("接收", action: accept).buttonStyle(.borderedProminent) }
            }.padding().navigationTitle("接收确认").interactiveDismissDisabled()
        }
    }
}
