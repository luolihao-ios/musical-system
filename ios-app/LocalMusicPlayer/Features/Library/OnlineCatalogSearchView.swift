import SwiftUI

@MainActor
struct OnlineCatalogSearchView: View {
    @Bindable var model: LibraryModel
    var initialResults: [CatalogTrack] = []
    var embeddedInNavigationStack: Bool = true
    var autoFocus: Bool = false

    @AppStorage("search.recentQueries") private var recentQueriesRaw = ""
    @State private var query = ""
    @State private var results: [CatalogTrack] = []
    @State private var suggestions: [String] = []
    @State private var suggestTask: Task<Void, Never>?
    @State private var loading = false
    @State private var searchFailed = false
    @State private var submittedQuery: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var message = ""
    @State private var searchGeneration = UUID()
    @State private var selectedSource: String = "all"
    @FocusState private var isSearchFocused: Bool

    private var recentQueries: [String] {
        recentQueriesRaw
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private var recommendedTerms: [String] {
        let lang = Locale.current.language.languageCode?.identifier ?? ""
        if lang.hasPrefix("zh") {
            return ["周杰伦", "轻音乐", "钢琴曲", "民谣", "爵士", "华语流行"]
        }
        return ["piano", "jazz", "acoustic", "electronic"]
    }

    private var availableSources: [String] {
        var seen = Set<String>()
        var list: [String] = []
        for track in results {
            let group = sourceGroup(for: track)
            if !group.isEmpty, seen.insert(group).inserted {
                list.append(group)
            }
        }
        return list
    }

    private var playableResults: [CatalogTrack] {
        filteredResults.filter { $0.previewURL != nil }
    }

    private var filteredResults: [CatalogTrack] {
        switch selectedSource {
        case "all":
            return results
        case "playable":
            return results.filter { $0.previewURL != nil }
        default:
            return results.filter { sourceGroup(for: $0) == selectedSource }
        }
    }

    private var isShowingSuggestions: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && submittedQuery != trimmed && !loading
    }

    private func sourceGroup(for track: CatalogTrack) -> String {
        if track.provider.hasPrefix("iTunes") { return "iTunes" }
        return track.provider
    }

    var body: some View {
        if embeddedInNavigationStack {
            NavigationStack {
                content
            }
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)

            if availableSources.count > 1 && !isShowingSuggestions {
                sourceFilterBar
                    .padding(.bottom, 8)
            }

            List {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && results.isEmpty {
                    if !recentQueries.isEmpty {
                        Section {
                            ForEach(recentQueries, id: \.self) { term in
                                Button {
                                    query = term
                                    startSearch()
                                } label: {
                                    Label(term, systemImage: "clock.arrow.circlepath")
                                }
                                .foregroundStyle(.primary)
                            }
                        } header: {
                            HStack {
                                Text("最近搜索")
                                Spacer()
                                Button("清空") { recentQueriesRaw = "" }
                                    .font(.caption)
                            }
                        }
                    }
                    Section("推荐搜索") {
                        ForEach(recommendedTerms, id: \.self) { term in
                            Button(term) { query = term; startSearch() }
                        }
                    }
                } else if isShowingSuggestions {
                    Section("搜索联想") {
                        if suggestions.isEmpty {
                            Button {
                                startSearch()
                            } label: {
                                Label(
                                    String(format: NSLocalizedString("搜索“%@”", comment: ""), query.trimmingCharacters(in: .whitespacesAndNewlines)),
                                    systemImage: "magnifyingglass"
                                )
                            }
                            .foregroundStyle(PlayerTheme.accent)
                        } else {
                            ForEach(suggestions, id: \.self) { term in
                                Button {
                                    query = term
                                    isSearchFocused = false
                                    startSearch()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(term)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Spacer()
                                        Image(systemName: "arrow.up.left")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if loading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在搜索多源曲库…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }

                if !isShowingSuggestions && submittedQuery != nil && !loading && filteredResults.isEmpty {
                    Text(searchFailed ? LocalizedStringKey("在线搜索暂不可用，请重试") : LocalizedStringKey("暂无在线搜索结果"))
                        .foregroundStyle(.secondary)
                } else if !isShowingSuggestions && !loading && !filteredResults.isEmpty && filteredResults.allSatisfy({ $0.previewURL == nil }) {
                    Text("找到曲目信息，暂无可试听音源").foregroundStyle(.secondary)
                }

                if !isShowingSuggestions {
                    ForEach(filteredResults) { track in
                        HStack(alignment: .center, spacing: 10) {
                            metadata(track)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture { playOnline(track) }
                            actions(track)
                                .fixedSize()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(RefreshBackdrop())
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 72) }
        .onAppear {
            if autoFocus {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    isSearchFocused = true
                }
            }
        }
        .onChange(of: query) { _, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                cancelSearch()
            } else if trimmed != submittedQuery {
                scheduleSuggestions(for: trimmed)
            }
        }
        .task { if results.isEmpty { results = initialResults } }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .alert("提示", isPresented: Binding(get: { !message.isEmpty }, set: { if !$0 { message = "" } })) {
            Button("好") { message = "" }
        } message: {
            Text(message)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索歌曲、歌手或专辑", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isSearchFocused)
                    .onSubmit { startSearch() }
                if !query.isEmpty {
                    Button {
                        query = ""
                        cancelSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())

            Button {
                isSearchFocused = false
                startSearch()
            } label: {
                Text("搜索")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(PlayerTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("search.submit")
        }
    }

    private var sourceFilterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                filterChip(id: "all", title: String(localized: "全部"))
                if results.contains(where: { $0.previewURL != nil }) {
                    filterChip(id: "playable", title: String(localized: "可试听"))
                }
                ForEach(availableSources, id: \.self) { source in
                    filterChip(id: source, title: source)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }

    private func filterChip(id: String, title: String) -> some View {
        let active = selectedSource == id
        return Button {
            selectedSource = id
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(active ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    active ? AnyShapeStyle(PlayerTheme.accent) : AnyShapeStyle(.regularMaterial),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private func playOnline(_ track: CatalogTrack) {
        guard track.previewURL != nil else { return }
        if model.currentTrackID != track.previewID {
            NotificationCenter.default.post(name: .openNowPlayingPanel, object: nil)
        }
        let queue = playableResults
        Task {
            do { try await model.toggleCatalogPreview(track, in: queue) }
            catch { message = String(format: NSLocalizedString("试听失败：%@", comment: ""), error.localizedDescription) }
        }
    }

    private func metadata(_ track: CatalogTrack) -> some View {
        let isCurrent = model.currentTrackID == track.previewID
        return HStack(spacing: 10) {
            CachedRemoteImage(url: track.artworkURL, cornerRadius: 9, maxPixelSize: 160)
                .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .foregroundStyle(isCurrent ? PlayerTheme.accent : Color.primary)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(2)
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
                    playOnline(track)
                } label: {
                    Group {
                        if pending {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: selected && model.isCurrentTrackPlaying ? "pause.fill" : "play.fill")
                                .font(.body.weight(.semibold))
                        }
                    }
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(format: NSLocalizedString(selected && (model.isCurrentTrackPlaying || pending) ? "暂停试听 %@" : "试听 %@", comment: ""), track.title))
            }
            if track.allowsDownload { downloadButton(track) }
        }
    }

    private func scheduleSuggestions(for keyword: String) {
        suggestTask?.cancel()
        suggestTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            let fetched = await OnlineCatalog.shared.suggest(query: keyword)
            guard !Task.isCancelled,
                  query.trimmingCharacters(in: .whitespacesAndNewlines) == keyword else { return }
            suggestions = fetched
        }
    }

    private func saveRecentQuery(_ keyword: String) {
        var list = recentQueries.filter { $0.caseInsensitiveCompare(keyword) != .orderedSame }
        list.insert(keyword, at: 0)
        recentQueriesRaw = list.prefix(8).joined(separator: "\n")
    }

    private func cancelSearch() {
        suggestTask?.cancel()
        suggestTask = nil
        suggestions = []
        searchTask?.cancel()
        searchTask = nil
        searchGeneration = UUID()
        submittedQuery = nil
        loading = false
        searchFailed = false
        selectedSource = "all"
        results = []
    }

    private func startSearch() {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        cancelSearch()
        guard !keyword.isEmpty else { return }
        saveRecentQuery(keyword)
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
                    if selectedSource == "all", visible.contains(where: { $0.previewURL != nil }) {
                        selectedSource = "playable"
                    }
                })
                guard searchGeneration == generation, !Task.isCancelled else { return }
                results = found
                if selectedSource == "all", found.contains(where: { $0.previewURL != nil }) {
                    selectedSource = "playable"
                }
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
