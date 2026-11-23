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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let featured = recommendations.tracks.first {
                    featuredCard(featured)
                    if !recommendations.shelves.isEmpty {
                        shortcuts
                        ForEach(recommendations.shelves.filter { $0.id == "mixes" || $0.id == "albums" }) { shelf in
                            shelfRow(shelf)
                        }
                    }
                    if recommendations.tracks.count > 1 {
                        Text("继续发现").font(.title2.bold())
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 136), spacing: 14)], spacing: 14) {
                            ForEach(recommendations.tracks.dropFirst()) { track in trackCard(track) }
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
            .padding(.bottom, 84)
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
        .sheet(item: $selectedShelf) { shelf in
            NavigationStack {
                List(shelf.groups) { group in
                    NavigationLink {
                        groupTracks(group)
                    } label: {
                        Label(group.title, systemImage: shelf.id == "radio" ? "dot.radiowaves.left.and.right" : "music.note.list")
                    }
                }
                .navigationTitle(LocalizedStringKey(shelf.title))
            }
        }
        .sheet(item: $selectedGroup) { group in NavigationStack { groupTracks(group) } }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(greeting).font(.largeTitle.bold())
                Text("为你推荐好音乐").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: openSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.title3.weight(.semibold)).frame(width: 48, height: 48)
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
        Button { preview(track, in: recommendations.tracks) } label: {
            Color.indigo.opacity(0.38)
                .frame(height: 185)
                .overlay {
                    AsyncImage(url: track.artworkURL) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                    }
                }
                .clipped()
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("今日推荐").font(.title2.bold())
                            Text(track.title).font(.subheadline).lineLimit(1)
                            Text(track.artist).font(.caption).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        previewLabel(track).font(.caption.bold()).padding(10)
                            .background(.white.opacity(0.25), in: Capsule())
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22))
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
                            .frame(width: 45, height: 44).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15))
                        Text(LocalizedStringKey(shelf.title)).font(.caption.weight(.semibold))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 70)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func shelfRow(_ shelf: DiscoveryShelf) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(LocalizedStringKey(shelf.title)).font(.title2.bold())
                Spacer()
                Button("查看全部") { selectedShelf = shelf }.font(.subheadline)
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(shelf.groups) { group in
                        if let track = group.tracks.first {
                            Button { selectedGroup = group } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    cover(track, tint: mint).frame(width: 112)
                                    Text(LocalizedStringKey(group.title)).font(.caption.weight(.semibold)).lineLimit(2)
                                }
                                .frame(width: 112, alignment: .leading)
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
        return List {
            if !group.tracks.isEmpty {
                Button {
                    selectedGroup = nil
                    selectedShelf = nil
                    Task {
                        do { try await library.playCatalogGroup(isRadio ? group.tracks.shuffled() : group.tracks) }
                        catch { previewError = error.localizedDescription }
                    }
                } label: {
                    Label(isRadio ? String(localized: "开始电台") : String(localized: "播放全部"),
                          systemImage: isRadio ? "dot.radiowaves.left.and.right" : "play.fill")
                }
            }
            ForEach(group.tracks) { track in
                Button { play(track, in: group.tracks) } label: {
                    HStack {
                        cover(track, tint: mint).frame(width: 46)
                        VStack(alignment: .leading) {
                            Text(track.title)
                            Text(track.artist).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        previewLabel(track)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(LocalizedStringKey(group.title))
    }

    private func play(_ track: CatalogTrack, in queue: [CatalogTrack]) {
        selectedGroup = nil
        selectedShelf = nil
        preview(track, in: queue)
    }

    private func trackCard(_ track: CatalogTrack) -> some View {
        Button { preview(track) } label: {
            VStack(alignment: .leading, spacing: 8) {
                cover(track, tint: mint)
                Text(track.title).font(.headline).lineLimit(1)
                Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                previewLabel(track).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("discovery.track.\(track.id)")
    }

    private func cover(_ track: CatalogTrack, tint: Color) -> some View {
        tint.aspectRatio(1, contentMode: .fit)
            .overlay {
                AsyncImage(url: track.artworkURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else {
                        Image(systemName: "music.note").font(.title)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .accessibilityHidden(true)
    }

    private func previewLabel(_ track: CatalogTrack) -> some View {
        let playing = library.currentTrackID == track.previewID &&
            (library.isCurrentTrackPlaying || library.catalogPreviewLoadingID == track.id)
        return Label(playing ? String(localized: "暂停") : String(localized: "试听"),
                     systemImage: playing ? "pause.fill" : "play.fill")
            .foregroundStyle(.primary)
    }

    private func preview(_ track: CatalogTrack, in queue: [CatalogTrack] = []) {
        Task {
            do { try await library.toggleCatalogPreview(track, in: queue) }
            catch { previewError = error.localizedDescription }
        }
    }
}
