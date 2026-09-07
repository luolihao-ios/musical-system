import SwiftUI

struct OnlineCatalogSearchView: View {
    @Bindable var model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [CatalogTrack] = []
    @State private var loading = false
    @State private var message = ""

    var body: some View {
        NavigationStack {
            List(results) { track in
                HStack {
                    VStack(alignment: .leading) { Text(track.title); Text(track.artist).font(.caption).foregroundStyle(.secondary); Text(track.license.displayName).font(.caption2) }
                    Spacer()
                    if track.license.allowsDownload { Button("下载") { Task { await download(track) } }.buttonStyle(.borderedProminent) }
                }
            }
            .overlay { if loading { ProgressView() } else if results.isEmpty { ContentUnavailableView("搜索公开音乐", systemImage: "globe", description: Text("搜索 Jamendo 等开放许可音乐")) } }
            .searchable(text: $query, prompt: "搜索歌曲或艺术家")
            .onSubmit(of: .search) { Task { await search() } }
            .navigationTitle("在线音乐")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } } }
            .alert("提示", isPresented: Binding(get: { !message.isEmpty }, set: { if !$0 { message = "" } })) { Button("好") { message = "" } } message: { Text(message) }
        }
    }

    private func search() async {
        loading = true; defer { loading = false }
        do { results = try await OnlineCatalog.shared.search(query: query) }
        catch { message = error.localizedDescription }
    }

    private func download(_ track: CatalogTrack) async {
        do {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("AiYueCatalogDownloads", isDirectory: true)
            let url = try await OnlineCatalog.shared.download(track, to: root) { _ in }
            await model.importFiles([ImportedFile(sourceURL: url, kind: .audio)])
            message = "已下载并加入全部歌曲"
        } catch { message = error.localizedDescription }
    }
}
