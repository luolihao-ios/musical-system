import SwiftUI

struct BaiduCoverSettingsView: View {
    @Bindable var library: LibraryModel
    @State private var key = ""
    @State private var configured = false
    @State private var message = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("密钥状态", value: configured ? "已配置" : "未配置")
                SecureField("百度 AppBuilder API Key", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("保存密钥并补全封面") {
                    do {
                        try BaiduSearchCredentials.save(key)
                        key = ""
                        configured = BaiduSearchCredentials.read() != nil
                        message = configured ? "密钥已保存在本机钥匙串" : "密钥已清除"
                        if configured { library.retryMissingCovers() }
                    } catch { message = error.localizedDescription }
                }
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || library.isCompletingResources)
                if configured {
                    Button("清除密钥", role: .destructive) {
                        library.cancelCoverSearch()
                        do { try BaiduSearchCredentials.save(""); configured = false; message = "已清除本机密钥" }
                        catch { message = error.localizedDescription }
                    }
                }
                Link("开通百度官方搜索 API", destination: URL(string: "https://ai.baidu.com/ai-doc/AppBuilder/pmaxd1hvy")!)
            } header: {
                Text("百度封面搜索")
            } footer: {
                Text("此测试版使用你自己的百度搜索额度。密钥仅存于本机钥匙串，不会写入诊断日志。图片搜索结果仍受原站点使用条款约束。")
            }
            Section {
                Button("重新查找缺失封面") { library.retryMissingCovers() }
                    .disabled(!configured || library.isCompletingResources)
                if library.isCompletingResources {
                    Button("暂停封面搜索") { library.cancelCoverSearch() }
                }
                if !library.coverSearchMessage.isEmpty { Text(library.coverSearchMessage).font(.footnote) }
                if !message.isEmpty { Text(message).font(.footnote) }
            } header: {
                Text("补全已有歌曲")
            } footer: {
                Text("导入后优先查找歌名相关封面，再查歌手的专辑封面。已有内嵌或自选封面会保留；歌词仅在播放页点击“查找歌词”后查询。")
            }
        }
        .navigationTitle("封面搜索")
        .onAppear { configured = BaiduSearchCredentials.read() != nil }
    }
}
