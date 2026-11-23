import Foundation
import Observation

struct DiscoveryGroup: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let tracks: [CatalogTrack]
}

struct DiscoveryShelf: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let groups: [DiscoveryGroup]
}

struct DiscoveryFeed: Codable, Sendable {
    let recommendations: [CatalogTrack]
    let shelves: [DiscoveryShelf]

    func filtered() -> Self {
        let cleanShelves = shelves.compactMap { shelf -> DiscoveryShelf? in
            let groups = shelf.groups.compactMap { group -> DiscoveryGroup? in
                let tracks = DiscoveryModel.playableTracks(group.tracks)
                return tracks.isEmpty ? nil : .init(id: group.id, title: group.title, tracks: tracks)
            }
            return groups.isEmpty ? nil : .init(id: shelf.id, title: shelf.title, groups: groups)
        }
        return .init(recommendations: DiscoveryModel.playableTracks(recommendations), shelves: cleanShelves)
    }
}

struct DiscoveryMarket: Sendable, Equatable {
    let region: String
    let regionalQuery: String
    let openQuery: String

    init(locale: Locale) {
        let identifier = locale.region?.identifier ?? "001"
        let queries: (regional: String, open: String)
        switch identifier {
        case "CN": queries = ("轻音乐", "piano")
        case "TW", "HK", "MO": queries = ("輕音樂", "acoustic")
        case "JP": queries = ("ピアノ", "piano")
        case "FR", "BE": queries = ("chanson", "chanson")
        default: queries = ("acoustic", "acoustic")
        }
        region = identifier
        regionalQuery = queries.regional
        openQuery = queries.open
    }
}

// 首页状态不依赖 LibraryModel 或音乐资料库。导入、收藏和删除不会替换推荐。
@MainActor
@Observable
final class DiscoveryModel {
    typealias Loader = @Sendable (DiscoveryMarket) async throws -> [CatalogTrack]
    private(set) var tracks: [CatalogTrack]
    private(set) var shelves: [DiscoveryShelf] = []
    private(set) var isLoading = false
    private(set) var isUnavailable = false
    private var didLoad = false
    private let market: DiscoveryMarket
    private let defaults: UserDefaults
    private let loader: Loader
    private let feedLoader: (@Sendable (DiscoveryMarket) async -> DiscoveryFeed)?
    private let isFixture: Bool
    private var cacheKey: String { "discovery.recommendations.v1.\(market.region)" }

    init(
        market: DiscoveryMarket = .init(locale: .current),
        defaults: UserDefaults = .standard,
        fixtureTracks: [CatalogTrack]? = nil,
        feedLoader: (@Sendable (DiscoveryMarket) async -> DiscoveryFeed)? = nil,
        loader: @escaping Loader = { market in await OnlineCatalog.shared.recommendations(for: market) }
    ) {
        self.market = market
        self.defaults = defaults
        self.loader = loader
        self.feedLoader = feedLoader
        isFixture = fixtureTracks != nil
        if let fixtureTracks {
            tracks = fixtureTracks
        } else if feedLoader != nil,
                  let data = defaults.data(forKey: "discovery.feed.v2.\(market.region)"),
                  let cached = try? JSONDecoder().decode(DiscoveryFeed.self, from: data).filtered() {
            tracks = cached.recommendations
            shelves = cached.shelves
        } else if let data = defaults.data(forKey: "discovery.recommendations.v1.\(market.region)"),
                  let cached = try? JSONDecoder().decode([CatalogTrack].self, from: data) {
            tracks = Self.playableTracks(cached)
        } else {
            tracks = []
        }
    }

    nonisolated static func playableTracks(_ results: [CatalogTrack]) -> [CatalogTrack] {
        var seen = Set<String>()
        var selected: [CatalogTrack] = []
        for track in results {
            guard let preview = track.previewURL, preview.scheme?.lowercased() == "https",
                  let host = preview.host, !host.isEmpty, !host.lowercased().hasSuffix(".invalid"),
                  seen.insert(track.id).inserted else { continue }
            selected.append(track)
            if selected.count == 12 { break }
        }
        return selected
    }

    func loadIfNeeded() async {
        guard !didLoad else { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading, !isFixture else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if let feedLoader {
                let feed = await feedLoader(market).filtered()
                try Task.checkCancellation()
                didLoad = true
                isUnavailable = feed.recommendations.isEmpty
                guard !feed.recommendations.isEmpty else { return }
                tracks = feed.recommendations
                shelves = feed.shelves
                if let data = try? JSONEncoder().encode(feed) {
                    defaults.set(data, forKey: "discovery.feed.v2.\(market.region)")
                }
                return
            }
            let results = Self.playableTracks(try await loader(market))
            try Task.checkCancellation()
            didLoad = true
            isUnavailable = results.isEmpty
            // 失败或空响应不清掉上一批可用推荐。
            guard !results.isEmpty else { return }
            tracks = results
            if let data = try? JSONEncoder().encode(results) { defaults.set(data, forKey: cacheKey) }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            didLoad = true
            isUnavailable = true
        }
    }
}
