import SwiftUI

@MainActor
struct OnlineCatalogSearchView: View {
    private enum Scope: Hashable { case online, local }
    @Bindable var model: LibraryModel
    var initialResults: [CatalogTrack] = []
    @State private var query = ""
    @State private var results: [CatalogTrack] = []
    @State private var loading = false
    @State private var searchFailed = false
    @State private var submittedQuery: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var message = ""
    @State private var searchGeneration = UUID()
    @State private var scope: Scope = .online

    private var localResults: [TrackSnapshot] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return model.tracks }
        return model.tracks.filter {
            [$0.title, $0.artist, $0.album].contains { $0.localizedStandardContains(term) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("音乐来源", selection: $scope) {
                    Text("在线音乐").tag(Scope.online)
                    Text("本地音乐").tag(Scope.local)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                if scope == .local {
                    ForEach(localResults) { track in
                        TrackRow(track: track, isCurrent: model.currentTrackID == track.id,
                                 isPlaying: model.isCurrentTrackPlaying) {
                            Task { try? await model.play(track, in: localResults) }
                        } toggleLike: {
                            try? model.toggleLike(track)
                        } delete: {
                            try? model.delete(track)
                        }
                    }
                    if localResults.isEmpty { Text("没有匹配的本地音乐").foregroundStyle(.secondary) }
                } else {
                    if query.isEmpty && results.isEmpty {
                        Section("推荐搜索") {
                            ForEach(["piano", "jazz", "acoustic", "electronic"], id: \.self) { term in
                                Button(term) { query = term; startSearch() }
                            }
                        }
                    }
                    if loading { ProgressView("正在搜索…") }
                    if submittedQuery != nil && !loading && results.isEmpty {
                        Text(searchFailed ? LocalizedStringKey("在线搜索暂不可用，请重试") : LocalizedStringKey("暂无在线搜索结果"))
                            .foregroundStyle(.secondary)
                    } else if !loading && !results.isEmpty && results.allSatisfy({ $0.previewURL == nil }) {
                        Text("找到曲目信息，暂无可试听音源").foregroundStyle(.secondary)
                    }
                    ForEach(results) { track in
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
                }
            }
            .scrollContentBackground(.hidden)
            .background(RefreshBackdrop())
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 72) }
            .searchable(text: $query, prompt: "搜索歌曲、歌手或专辑")
            .onSubmit(of: .search) { if scope == .online { startSearch() } }
            .onChange(of: query) { _, value in
                if value.trimmingCharacters(in: .whitespacesAndNewlines) != submittedQuery { cancelSearch() }
            }
            .task { if results.isEmpty { results = initialResults } }
            .navigationTitle("搜索")
            .alert("提示", isPresented: Binding(get: { !message.isEmpty }, set: { if !$0 { message = "" } })) { Button("好") { message = "" } } message: { Text(message) }
        }
    }

    private func metadata(_ track: CatalogTrack) -> some View {
        HStack(spacing: 10) {
            Color.accentColor.opacity(0.12).frame(width: 48, height: 48)
                .overlay {
                    AsyncImage(url: track.artworkURL) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { Image(systemName: "music.note").foregroundStyle(.secondary) }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title).lineLimit(2)
                Text(track.artist).font(.caption).foregroundStyle(.secondary)
                Text([track.provider, track.previewURL == nil && !track.allowsDownload ? String(localized: "仅曲目信息") : track.license.displayName]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                if case .failed(let reason) = model.catalogDownloads[track.id] {
                    Text(String(format: NSLocalizedString("下载失败：%@", comment: ""), reason)).font(.caption2).foregroundStyle(.red).lineLimit(2)
                }
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
                    if track.allowsDownload { downloadButton(track) }
        }
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchGeneration = UUID()
        submittedQuery = nil
        loading = false
        searchFailed = false
        results = []
    }

    private func startSearch() {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        cancelSearch()
        guard !keyword.isEmpty else { return }
        let generation = UUID()
        searchGeneration = generation
        submittedQuery = keyword
        loading = true
        searchTask = Task { @MainActor in
            defer {
                if searchGeneration == generation { loading = false; searchTask = nil }
            }
            do {
                let found = try await OnlineCatalog.shared.search(query: keyword, onUpdate: { visible in
                    guard searchGeneration == generation, !Task.isCancelled else { return }
                    results = visible
                })
                guard searchGeneration == generation, !Task.isCancelled else { return }
                results = found
            } catch {
                guard searchGeneration == generation, !Task.isCancelled else { return }
                searchFailed = true
            }
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
