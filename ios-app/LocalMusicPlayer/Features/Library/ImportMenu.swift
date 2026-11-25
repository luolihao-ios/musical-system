import SwiftUI

enum CompanionTransferApp {
    static let storeURL = URL(string: "https://apps.apple.com/app/id6807546039")!
}

struct ImportMenu: View {
    let importFiles: () -> Void
    let scanLocalAudio: () -> Void
    let authorizeMusicFolder: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        Menu {
            Button(action: importFiles) {
                Label("从“文件”导入", systemImage: "folder")
            }
            Button(action: scanLocalAudio) {
                Label("扫描本地音频", systemImage: "waveform")
            }
            Button(action: authorizeMusicFolder) {
                Label("授权音乐文件夹", systemImage: "checkmark.shield")
            }
            Divider()
            Button {
                openURL(CompanionTransferApp.storeURL)
            } label: {
                Label("使用爱乐互传导入", systemImage: "arrow.left.arrow.right.circle")
            }
            .accessibilityIdentifier("import.transferApp")
        } label: {
            Label("导入音乐", systemImage: "square.and.arrow.down")
                .labelStyle(.titleAndIcon)
        }
    }
}
