import XCTest
@testable import LocalMusicPlayer

final class DiscoveryFeedTests: XCTestCase {
    func testArchiveSearchPrefersMatchingSongOverFirstSongOnAlbum() {
        let first = track("1", title: "Psycho Logic")
        let match = track("10", title: "Haunting Solitude")
        let group = DiscoveryGroup(id: "album", title: "Album", tracks: [first, match])
        XCTAssertEqual(OnlineCatalog.archiveSearchTracks(in: [group], query: "haunting solitude").map(\.id), ["10"])
    }

    private func track(_ id: String, title: String) -> CatalogTrack {
        let url = URL(string: "https://example.org/audio.mp3")!
        return CatalogTrack(id: id, title: title, artist: "Artist", audioURL: url, license: .publicDomain, previewURL: url)
    }
    func testArchiveDiscoveryUsesSourcePopularityAndCollectionDates() {
        let top = OnlineCatalog.archiveQuery(query: nil, order: .popular, limit: 4)
        let recent = OnlineCatalog.archiveQuery(query: nil, order: .recent, limit: 4)
        XCTAssertEqual(top.first { $0.name == "sort[]" }?.value, "downloads desc")
        XCTAssertEqual(recent.first { $0.name == "sort[]" }?.value, "publicdate desc")
        XCTAssertEqual(top.first { $0.name == "q" }?.value,
                       "collection:jamendo-albums AND (licenseurl:*creativecommons.org* OR licenseurl:*publicdomain*)")
    }

    func testFeedOnlyShowsShelvesWithPlayableTracksAndDeduplicatesRecommendations() {
        let a = CatalogTrack(id: "a", title: "A", artist: "Artist",
                             audioURL: URL(string: "https://example.org/a.mp3")!, license: .publicDomain,
                             previewURL: URL(string: "https://example.org/a.mp3"))
        let invalid = CatalogTrack(id: "b", title: "B", artist: "Artist",
                                   audioURL: URL(string: "https://example.org/b.mp3")!, license: .unknown)
        let feed = DiscoveryFeed(recommendations: [a, a, invalid], shelves: [
            DiscoveryShelf(id: "empty", title: "空", groups: [.init(id: "g", title: "空", tracks: [invalid])]),
            DiscoveryShelf(id: "top", title: "热门榜单", groups: [.init(id: "h", title: "热门榜单", tracks: [a])])
        ]).filtered()
        XCTAssertEqual(feed.recommendations.map(\.id), ["a"])
        XCTAssertEqual(feed.shelves.map(\.id), ["top"])
    }
}
