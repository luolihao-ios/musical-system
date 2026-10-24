import SwiftUI

struct OnlineCatalogSearchView: View {
    @Bindable var model: LibraryModel
    var initialResults: [CatalogTrack] = []
    @State private var query = ""
    @State private var results: [CatalogTrack] = []
    @State private var loading = false
    @State private var message = ""
    @State private var searchGeneration = UUID()

    var body: some View {
        NavigationStack {
            List(results) { track in
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        metadata(track).frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
                        actions(track)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        metadata(track)
                        actions(track)
                    }
                }
                .padding(.vertical, 4)
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 72) }
            .overlay { if loading { ProgressView() } else if results.isEmpty { ContentUnavailableView("搜索公开音乐", systemImage: "globe", description: Text("搜索 Jamendo 等开放许可音乐")) } }
            .searchable(text: $query, prompt: "搜索歌曲、艺术家或歌词关键词")
            .onSubmit(of: .search) { Task { await search() } }
            .task { if results.isEmpty { results = initialResults } }
            .navigationTitle("在线音乐")
            .alert("提示", isPresented: Binding(get: { !message.isEmpty }, set: { if !$0 { message = "" } })) { Button("好") { message = "" } } message: { Text(message) }
        }
    }

    private func metadata(_ track: CatalogTrack) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(track.title).lineLimit(2)
            Text(track.artist).font(.caption).foregroundStyle(.secondary)
            Text([track.provider, track.license.displayName].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            if case .failed(let reason) = model.catalogDownloads[track.id] {
                Text(String(format: NSLocalizedString("下载失败：%@", comment: ""), reason)).font(.caption2).foregroundStyle(.red).lineLimit(2)
            }
        }
    }

    private func actions(_ track: CatalogTrack) -> some View {
        HStack(spacing: 8) {
                    if track.previewURL != nil {
                        let selected = model.currentTrackID == track.previewID
                        let pending = model.catalogPreviewLoadingID == track.id
                        Button {
                            Task {
                                do { try await model.toggleCatalogPreview(track) }
                                catch { message = String(format: NSLocalizedString("试听失败：%@", comment: ""), error.localizedDescription) }
                            }
                        } label: {
                            Image(systemName: selected && (model.isCurrentTrackPlaying || pending) ? "pause.fill" : "play.fill")
                                .font(.body.weight(.semibold)).frame(width: 44, height: 44)
                                .background(Color.accentColor.opacity(0.1), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(format: NSLocalizedString(selected && (model.isCurrentTrackPlaying || pending) ? "暂停试听 %@" : "试听 %@", comment: ""), track.title))
                    }
                    if track.license.allowsDownload { downloadButton(track) }
        }
    }

    private func search() async {
        let generation = UUID()
        searchGeneration = generation
        let submittedQuery = query
        loading = true; defer { if searchGeneration == generation { loading = false } }
        do {
            let found = try await OnlineCatalog.shared.search(query: submittedQuery)
            guard searchGeneration == generation else { return }
            results = found
        }
        catch {
            guard searchGeneration == generation else { return }
            // 搜索服务不可用时保持空结果，不把网络或供应商错误暴露给用户。
            results = []
        }
    }

    private func downloadButton(_ track: CatalogTrack) -> some View {
        let state = model.catalogDownloads[track.id]
        return Button {
            Task { await model.downloadCatalogTrack(track) }
        } label: {
            ZStack {
                Circle().stroke(Color.accentColor.opacity(0.15), lineWidth: 3)
                switch state {
                case .downloading(let progress):
                    if let progress {
                        Circle().trim(from: 0, to: progress)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(progress * 100))").font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    } else { ProgressView().controlSize(.small) }
                case .importing: ProgressView().controlSize(.small)
                case .completed: Image(systemName: "checkmark").foregroundStyle(.green)
                case .failed: Image(systemName: "arrow.clockwise").foregroundStyle(.red)
                case nil: Image(systemName: "arrow.down")
                }
            }
            .font(.body.weight(.semibold)).frame(width: 32, height: 32).padding(6)
        }
        .buttonStyle(.plain)
        .disabled(state?.isBusy == true || state == .completed)
        .accessibilityLabel(downloadLabel(state, title: track.title))
        .accessibilityValue(downloadValue(state))
    }

    private func downloadLabel(_ state: CatalogDownloadState?, title: String) -> String {
        switch state {
        case .downloading: String(format: NSLocalizedString("正在下载 %@", comment: ""), title)
        case .importing: String(format: NSLocalizedString("正在导入 %@", comment: ""), title)
        case .completed: String(format: NSLocalizedString("已下载 %@", comment: ""), title)
        case .failed: String(format: NSLocalizedString("重试下载 %@", comment: ""), title)
        case nil: String(format: NSLocalizedString("下载 %@", comment: ""), title)
        }
    }

    private func downloadValue(_ state: CatalogDownloadState?) -> String {
        if case .downloading(let progress) = state, let progress { return "\(Int(progress * 100))%" }
        return ""
    }
}
