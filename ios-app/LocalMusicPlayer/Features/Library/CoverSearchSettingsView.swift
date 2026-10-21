import SwiftUI

struct CoverSearchSettingsView: View {
    @Bindable var library: LibraryModel
    var body: some View {
        Form {
            Section {
                Text("导入后立即显示程序化封面并可播放，后台再逐首替换找到的封面。已有内嵌或自选封面会保留。")
                Text("中文歌优先网易、QQ、酷狗；英文歌优先 iTunes、MusicBrainz 等，失败后交叉回退。百度查询已停用，不需要填写密钥。")
            } header: { Text("自动补全封面") }
            Section {
                Button("重新查找缺失封面") { library.retryMissingCovers() }
                    .disabled(library.isCompletingResources)
                if library.isCompletingResources {
                    Button("暂停封面搜索") { library.cancelCoverSearch() }
                }
                if !library.coverSearchMessage.isEmpty { Text(library.coverSearchMessage).font(.footnote) }
                ShareLink(item: CoverSearchDiagnostics.fileURL) {
                    Label("导出封面查询日志", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("单首以约五秒为查找目标，已返回候选的图片最多再收尾三秒；不影响导入和播放。没有结果就保留生成图。歌词仅在播放页主动查找。")
            }
        }
        .navigationTitle("封面补全")
        .task { CoverSearchDiagnostics.log("打开封面补全设置") }
    }
}
