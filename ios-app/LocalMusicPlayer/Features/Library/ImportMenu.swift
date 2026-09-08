import SwiftUI

struct ImportMenu: View {
    let importFiles: () -> Void
    let scanLocalAudio: () -> Void
    let authorizeMusicFolder: () -> Void

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
        } label: {
            Label("导入", systemImage: "plus.circle.fill")
        }
    }
}
