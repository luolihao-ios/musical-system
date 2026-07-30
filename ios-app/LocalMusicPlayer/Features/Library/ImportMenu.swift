import SwiftUI

struct ImportMenu: View {
    let importFiles: () -> Void
    let importSystemLibrary: () -> Void

    var body: some View {
        Menu {
            Button(action: importFiles) {
                Label("从“文件”导入", systemImage: "folder")
            }
            Button(action: importSystemLibrary) {
                Label("读取设备音乐资料库", systemImage: "music.note.house")
            }
        } label: {
            Label("导入", systemImage: "plus.circle.fill")
        }
    }
}
