import SwiftUI

@MainActor
struct DiscoveryView: View {
    @Bindable var recommendations: DiscoveryModel
    @Bindable var library: LibraryModel
    let openSearch: () -> Void
    @State private var previewError: String?
    @State private var selectedShelf: DiscoveryShelf?
    @State private var selectedGroup: DiscoveryGroup?

    private let mint = PlayerTheme.accent.opacity(0.13)

    private var pagedRecommendations: [[CatalogTrack]] {
        let items = Array(recommendations.tracks.dropFirst())
        guard !items.isEmpty else { return [] }
        return stride(from: 0, to: items.count, by: 3).map { start in
            Array(items[start..<min(start + 3, items.count)])
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let featured = recommendations.tracks.first {
                    featuredCard(featured)
                    if !recommendations.shelves.isEmpty {
                        shortcuts
                    }
                    if !pagedRecommendations.isEmpty {
                        everyoneListeningSection
                    }
                    if !recommendations.shelves.isEmpty {
                        ForEach(recommendations.shelves.filter { $0.id == "mixes" || $0.id == "albums" }) { shelf in
                            shelfRow(shelf)
                        }
                    }
                    if recommendations.isUnavailable {
                        Label("显示上次推荐", systemImage: "clock.arrow.circlepath")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: 920)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 88)
            .frame(maxWidth: .infinity)
        }
        .background(RefreshBackdrop())
        .accessibilityIdentifier("discovery.home")
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { Task { await recommendations.loadIfNeeded() } }
        .refreshable { await recommendations.refresh() }
        .alert("提示", isPresented: Binding(
            get: { previewError != nil },
            set: { if !$0 { previewError = nil } }
        )) {
            Button("好", role: .cancel) { previewError = nil }
        } message: {
            Text(previewError ?? "")
        }
        .navigationDestination(item: $selectedShelf) { shelf in
            List(shelf.groups) { group in
                NavigationLink {
                    groupTracks(group)
                } label: {
                    HStack(spacing: 12) {
                        CachedRemoteImage(url: group.tracks.first?.artworkURL, cornerRadius: 8, maxPixelSize: 160)
                            .frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(LocalizedStringKey(group.title)).font(.headline)
                            Text("\(group.tracks.count) 首")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(RefreshBackdrop())
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 72) }
            .navigationTitle(LocalizedStringKey(shelf.title))
        }
        .navigationDestination(item: $selectedGroup) { group in
            groupTracks(group)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting).font(.largeTitle.bold())
                Text("为你推荐好音乐").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: openSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("搜索")
        }
    }

    private var greeting: LocalizedStringKey {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "早上好"
        case 12..<18: "下午好"
        default: "晚上好"
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("在线推荐", systemImage: "sparkles").font(.headline)
            if recommendations.isUnavailable {
                Text("暂时没有在线推荐").font(.title2.bold())
                Button("重试") { Task { await recommendations.refresh() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(recommendations.isLoading)
            } else {
                ProgressView("正在加载在线推荐…")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(mint, in: RoundedRectangle(cornerRadius: 24))
    }

    private func featuredCard(_ track: CatalogTrack) -> some View {
        let playing = library.currentTrackID == track.previewID &&
            (library.isCurrentTrackPlaying || library.catalogPreviewLoadingID == track.id)
        return Button { preview(track, in: recommendations.tracks) } label: {
            ZStack(alignment: .bottomLeading) {
                CachedRemoteImage(
                    url: track.artworkURL,
                    cornerRadius: 24,
                    maxPixelSize: 800,
                    placeholderTint: Color.indigo.opacity(0.45)
                )
                .frame(height: 196)
                .frame(maxWidth: .infinity)
                .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.25), .black.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("今日推荐")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.22), in: Capsule())
                        Text(track.title)
                            .font(.title3.bold())
                            .lineLimit(1)
                        Text([track.artist, track.provider].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .opacity(0.88)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Group {
                        if library.catalogPreviewLoadingID == track.id {
                            ProgressView().tint(.white)
                        } else {
                            Label(playing ? String(localized: "暂停") : String(localized: "播放"),
                                  systemImage: playing ? "pause.fill" : "play.fill")
                                .font(.caption.bold())
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.24), in: Capsule())
                }
                .foregroundStyle(.white)
                .padding(18)
            }
            .frame(height: 196)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("discovery.track.\(track.id)")
    }

    private var shortcuts: some View {
        let icons = ["chart": "flame.fill", "mixes": "star.fill", "radio": "dot.radiowaves.left.and.right",
                     "recent": "sparkles"]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], spacing: 8) {
            ForEach(recommendations.shelves.filter { $0.id != "albums" }) { shelf in
                Button { selectedShelf = shelf } label: {
                    VStack(spacing: 6) {
                        Image(systemName: icons[shelf.id] ?? "music.note")
                            .font(.title3).foregroundStyle(PlayerTheme.accent)
                            .frame(width: 46, height: 46)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        Text(LocalizedStringKey(shelf.title))
                            .font(.caption.weight(.semibold))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 72)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var everyoneListeningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("继续发现").font(.title3.bold())
                Spacer()
                Button {
                    Task {
                        NotificationCenter.default.post(name: .openNowPlayingPanel, object: nil)
                        do { try await library.playCatalogGroup(recommendations.tracks) }
                        catch { previewError = error.localizedDescription }
                    }
                } label: {
                    Label("播放全部", systemImage: "play.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(pagedRecommendations.enumerated()), id: \.offset) { _, column in
                        VStack(spacing: 10) {
                            ForEach(column) { track in
                                compactSongRow(track)
                            }
                        }
                        .frame(width: 286)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func compactSongRow(_ track: CatalogTrack) -> some View {
        let isCurrent = library.currentTrackID == track.previewID
        let isLoading = library.catalogPreviewLoadingID == track.id
        let isPlaying = isCurrent && library.isCurrentTrackPlaying
        return Button { preview(track, in: recommendations.tracks) } label: {
            HStack(spacing: 12) {
                CachedRemoteImage(url: track.artworkURL, cornerRadius: 10, maxPixelSize: 160, placeholderTint: mint)
                    .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isCurrent ? PlayerTheme.accent : Color.primary)
                        .lineLimit(1)
                    Text([track.artist, track.provider].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle")
                        .font(.title3)
                        .foregroundStyle(isCurrent ? PlayerTheme.accent : .secondary)
                }
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("discovery.track.\(track.id)")
    }

    private func shelfRow(_ shelf: DiscoveryShelf) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(LocalizedStringKey(shelf.title)).font(.title3.bold())
                Spacer()
                Button("查看全部") { selectedShelf = shelf }.font(.subheadline)
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(shelf.groups) { group in
                        if let track = group.tracks.first {
                            Button { selectedGroup = group } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    CachedRemoteImage(url: track.artworkURL, cornerRadius: 14, maxPixelSize: 300, placeholderTint: mint)
                                        .frame(width: 122, height: 122)
                                        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
                                    Text(LocalizedStringKey(group.title))
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(2)
                                }
                                .frame(width: 122, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func groupTracks(_ group: DiscoveryGroup) -> some View {
        let isRadio = group.id.hasPrefix("radio-")
        let heroCover = group.tracks.first?.artworkURL
        return List {
            Section {
                VStack(spacing: 14) {
                    CachedRemoteImage(url: heroCover, cornerRadius: 20, maxPixelSize: 500, placeholderTint: mint)
                        .frame(width: 164, height: 164)
                        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                    Text(LocalizedStringKey(group.title))
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    if !group.tracks.isEmpty {
                        Button {
                            Task {
                                NotificationCenter.default.post(name: .openNowPlayingPanel, object: nil)
                                do { try await library.playCatalogGroup(isRadio ? group.tracks.shuffled() : group.tracks) }
                                catch { previewError = error.localizedDescription }
                            }
                        } label: {
                            Label(isRadio ? String(localized: "开始电台") : String(localized: "播放全部"),
                                  systemImage: isRadio ? "dot.radiowaves.left.and.right" : "play.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 11)
                                .background(PlayerTheme.accent, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                ForEach(Array(group.tracks.enumerated()), id: \.element.id) { index, track in
                    Button { preview(track, in: group.tracks) } label: {
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            CachedRemoteImage(url: track.artworkURL, cornerRadius: 8, maxPixelSize: 160, placeholderTint: mint)
                                .frame(width: 46, height: 46)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.title)
                                    .foregroundStyle(library.currentTrackID == track.previewID ? PlayerTheme.accent : Color.primary)
                                    .lineLimit(1)
                                Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if library.catalogPreviewLoadingID == track.id {
                                ProgressView().controlSize(.small)
                            } else if library.currentTrackID == track.previewID && library.isCurrentTrackPlaying {
                                Image(systemName: "pause.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(PlayerTheme.accent)
                            } else {
                                Image(systemName: "play.circle")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(RefreshBackdrop())
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 72) }
        .navigationTitle(LocalizedStringKey(group.title))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func preview(_ track: CatalogTrack, in queue: [CatalogTrack] = []) {
        let alreadyCurrent = library.currentTrackID == track.previewID
        if !alreadyCurrent {
            NotificationCenter.default.post(name: .openNowPlayingPanel, object: nil)
        }
        Task {
            do { try await library.toggleCatalogPreview(track, in: queue) }
            catch { previewError = error.localizedDescription }
        }
    }
}
