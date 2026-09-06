import SwiftUI

struct ImportMenu: View {
    let importFiles: () -> Void
    let importSystemLibrary: () -> Void
    var completeResources: () -> Void = {}
    var authorizeFolders: () -> Void = {}

    var body: some View {
        Menu {
            Button(action: importFiles) {
                Label("从“文件”导入", systemImage: "folder")
            }
            Button(action: importSystemLibrary) {
                Label("读取设备音乐资料库", systemImage: "music.note.house")
            }
            Button(action: completeResources) { Label("联网补全缺失歌词与封面", systemImage: "network") }
            Button(action: authorizeFolders) { Label("设置自动扫描文件夹", systemImage: "folder.badge.plus") }
        } label: {
            Label("导入", systemImage: "plus.circle.fill")
        }
    }
}
