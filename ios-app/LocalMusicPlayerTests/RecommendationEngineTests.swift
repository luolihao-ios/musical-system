import XCTest
@testable import LocalMusicPlayer

@MainActor
final class RecommendationEngineTests: XCTestCase {
    func testTimeDecayHalvesAffinityAfterFourteenDays() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = DecayedAffinity(score: 10.0, updatedAt: base)
        let half = TasteProfileStore.decayed(entry, at: base.addingTimeInterval(14 * 86_400))
        XCTAssertEqual(half, 5.0, accuracy: 0.001)
    }

    func testPlaybackOutcomeRewardsCompletionAndPenalizesQuickSkip() {
        let fileURL = temporaryProfileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = TasteProfileStore(fileURL: fileURL)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        store.recordPlaybackOutcome(
            trackID: "online-preview-netease-1",
            artist: "陈奕迅",
            playedSeconds: 200,
            duration: 240,
            wasManualSkip: false,
            now: now
        )
        store.recordPlaybackOutcome(
            trackID: "online-preview-netease-2",
            artist: "纯音乐",
            playedSeconds: 6,
            duration: 180,
            wasManualSkip: true,
            now: now
        )

        let snap = store.snapshot(now: now, refreshNonce: 0, includeOnlineFavorites: false)
        XCTAssertEqual(snap.artistAffinities["陈奕迅"] ?? 0, 4.0, accuracy: 0.001)
        XCTAssertEqual(snap.artistAffinities["纯音乐"] ?? 0, -3.5, accuracy: 0.001)
        XCTAssertEqual(snap.trackFeedback["netease-1"]?.completeCount, 1)
        XCTAssertEqual(snap.trackFeedback["netease-2"]?.quickSkipCount, 1)
        XCTAssertTrue(store.needsHomeRefresh)
    }

    func testDislikeAndRepeatedQuickSkipExcludeTrack() {
        let fileURL = temporaryProfileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = TasteProfileStore(fileURL: fileURL)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        store.recordDislike(trackID: "netease-bad", artist: "歌手A", now: now)
        store.recordPlaybackOutcome(
            trackID: "netease-skip2", artist: "歌手B",
            playedSeconds: 5, duration: 200, wasManualSkip: true, now: now
        )
        store.recordPlaybackOutcome(
            trackID: "netease-skip2", artist: "歌手B",
            playedSeconds: 4, duration: 200, wasManualSkip: true, now: now.addingTimeInterval(30)
        )

        let snap = store.snapshot(now: now.addingTimeInterval(60), refreshNonce: 0, includeOnlineFavorites: false)
        XCTAssertNil(RecommendationEngine.score(RecallCandidate(track: makeTrack(id: "netease-bad", artist: "歌手A"), channel: .dailyFresh), taste: snap, now: now))
        XCTAssertNil(RecommendationEngine.score(RecallCandidate(track: makeTrack(id: "netease-skip2", artist: "歌手B"), channel: .dailyFresh), taste: snap, now: now))

        store.recordFavorite(artist: "歌手A", trackID: "netease-bad", isLiked: true, now: now)
        let unblocked = store.snapshot(now: now, refreshNonce: 0, includeOnlineFavorites: false)
        XCTAssertNotNil(RecommendationEngine.score(RecallCandidate(track: makeTrack(id: "netease-bad", artist: "歌手A"), channel: .coreArtist), taste: unblocked, now: now))
    }

    func testCanonicalIDAndLocalLibrarySeeding() {
        XCTAssertEqual(TasteProfileStore.canonicalTrackID("online-preview-netease-99"), "netease-99")
        XCTAssertEqual(TasteProfileStore.canonicalTrackID("netease-99"), "netease-99")

        let fileURL = temporaryProfileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = TasteProfileStore(fileURL: fileURL)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let tracks = [
            TrackSnapshot(id: "l1", title: "晴天", artist: "周杰伦", album: "", duration: 240, sourceKind: .importedFile, sourceReference: "/1.mp3", artworkReference: nil, isLiked: true),
            TrackSnapshot(id: "l2", title: "七里香", artist: "周杰伦", album: "", duration: 240, sourceKind: .importedFile, sourceReference: "/2.mp3", artworkReference: nil, isLiked: false),
            TrackSnapshot(id: "l3", title: "默认", artist: "爱乐之城", album: "", duration: 180, sourceKind: .importedFile, sourceReference: "/3.mp3", artworkReference: nil, isLiked: true)
        ]
        store.seedFromLocalLibrary(tracks, now: now)
        let snap = store.snapshot(now: now, refreshNonce: 0, includeOnlineFavorites: false)
        XCTAssertEqual(snap.artistAffinities["周杰伦"] ?? 0, 4.0, accuracy: 0.001)
        XCTAssertNil(snap.artistAffinities["爱乐之城"])
    }

    func testRankingPrefersFullLengthOverSnippetAndRotatesFatiguedHero() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let full = makeTrack(id: "netease-full", artist: "毛不易", provider: "网易云音乐")
        let snippet = makeTrack(id: "itunes-CN-1", artist: "毛不易", provider: "iTunes · CN")
        let fatigued = makeTrack(id: "netease-stale", artist: "陈奕迅", provider: "网易云音乐")
        let fresh = makeTrack(id: "netease-fresh", artist: "林俊杰", provider: "网易云音乐")

        let fileURL = temporaryProfileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = TasteProfileStore(fileURL: fileURL)
        store.recordFavorite(artist: "毛不易", trackID: "seed-mao", isLiked: true, now: now)
        store.recordFavorite(artist: "陈奕迅", trackID: "seed-eason", isLiked: true, now: now)
        store.recordHomeImpressions(["netease-stale"], now: now.addingTimeInterval(-3600))
        store.recordPlaybackOutcome(
            trackID: "netease-stale", artist: "陈奕迅",
            playedSeconds: 45, duration: 240, wasManualSkip: false,
            now: now.addingTimeInterval(-1800)
        )

        let snap = store.snapshot(now: now, refreshNonce: 0, includeOnlineFavorites: false)
        let fullScore = RecommendationEngine.score(RecallCandidate(track: full, channel: .coreArtist), taste: snap, now: now) ?? -999
        let snippetScore = RecommendationEngine.score(RecallCandidate(track: snippet, channel: .coreArtist), taste: snap, now: now) ?? -999
        XCTAssertGreaterThan(fullScore, snippetScore)

        let ranked = RecommendationEngine.rankAndDiversify([
            RecallCandidate(track: fatigued, channel: .coreArtist),
            RecallCandidate(track: fresh, channel: .dailyFresh)
        ], taste: snap, limit: 2, now: now)
        XCTAssertEqual(ranked.first?.id, "netease-fresh")
    }

    func testRankAndDiversifyEnforcesArtistSpacingAndCap() {
        let fileURL = temporaryProfileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = TasteProfileStore(fileURL: fileURL)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        store.recordFavorite(artist: "Artist0", trackID: "seed-0", isLiked: true, now: now)
        let snap = store.snapshot(now: now, refreshNonce: 0, includeOnlineFavorites: false)

        var candidates: [RecallCandidate] = []
        for idx in 0..<6 {
            candidates.append(RecallCandidate(track: makeTrack(id: "a-\(idx)", artist: "Artist0"), channel: .coreArtist))
        }
        for idx in 1...6 {
            candidates.append(RecallCandidate(track: makeTrack(id: "other-\(idx)", artist: "Artist\(idx)"), channel: idx <= 3 ? .exploration : .dailyFresh))
        }

        let ranked = RecommendationEngine.rankAndDiversify(candidates, taste: snap, limit: 10, now: now)
        let artist0Count = ranked.filter { $0.artist == "Artist0" }.count
        XCTAssertLessThanOrEqual(artist0Count, 2)
        for pair in zip(ranked, ranked.dropFirst()) {
            XCTAssertNotEqual(pair.0.artist, pair.1.artist)
        }
    }

    func testContinuationPivotsAwayFromQuickSkippedArtist() {
        let fileURL = temporaryProfileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = TasteProfileStore(fileURL: fileURL)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        store.recordFavorite(artist: "陶喆", trackID: "fav-tao", isLiked: true, now: now)
        store.recordPlaybackOutcome(
            trackID: "bad-song", artist: "轻音乐合集",
            playedSeconds: 5, duration: 200, wasManualSkip: true, now: now
        )
        let snap = store.snapshot(now: now, refreshNonce: 0, includeOnlineFavorites: false)
        let skippedTrack = TrackSnapshot(
            id: "online-preview-bad-song", title: "白噪音", artist: "轻音乐合集",
            album: "网易云音乐", duration: 200, sourceKind: .onlinePreview,
            sourceReference: "https://example.org/a.mp3"
        )
        let queries = RecommendationEngine.continuationQueries(for: skippedTrack, taste: snap)
        XCTAssertFalse(queries.isEmpty)
        XCTAssertNotEqual(queries.first, "轻音乐合集")
        XCTAssertEqual(queries.first, "陶喆")
    }

    private func temporaryProfileURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("taste-test-\(UUID()).json")
    }

    private func makeTrack(id: String, artist: String, provider: String = "网易云音乐") -> CatalogTrack {
        let url = URL(string: "https://example.org/\(id).mp3")!
        let art = URL(string: "https://example.org/\(id).jpg")!
        return CatalogTrack(
            id: id, title: "Track \(id)", artist: artist,
            audioURL: url, license: .unknown, provider: provider,
            previewURL: url, artworkURL: art
        )
    }
}
