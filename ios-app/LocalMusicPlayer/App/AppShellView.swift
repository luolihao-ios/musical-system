import SwiftUI

struct AppShellView: View {
    var body: some View {
        TabView {
            NavigationStack {
                ContentUnavailableView(
                    "还没有本地音乐",
                    systemImage: "music.note.list",
                    description: Text("从“文件”或设备音乐资料库导入")
                )
                .navigationTitle("音乐库")
            }
            .tabItem {
                Label("音乐库", systemImage: "music.note.house")
            }

            NavigationStack {
                ContentUnavailableView(
                    "还没有歌单",
                    systemImage: "music.note.list",
                    description: Text("创建一个歌单整理喜欢的音乐")
                )
                .navigationTitle("歌单")
            }
            .tabItem {
                Label("歌单", systemImage: "rectangle.stack")
            }

            NavigationStack {
                List {
                    LabeledContent("本地播放", value: "不联网下载")
                    LabeledContent("最低系统", value: "iOS 17")
                }
                .navigationTitle("设置")
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
        }
        .tint(PlayerTheme.accent)
    }
}
