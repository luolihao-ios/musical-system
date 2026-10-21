import SwiftData
import XCTest
@testable import LocalMusicPlayer

@MainActor
final class CoverSearchHistoryTests: XCTestCase {
    private func song() -> TrackRecord {
        TrackRecord(id: "history", title: "测试歌曲", artist: "歌手", album: "专辑", duration: 120,
            sourceKind: .importedFile, sourceReference: "/music/song.mp3", artworkReference: "/music/artwork-generated.jpg")
    }

    func testLegacyGeneratedCoverIsEligibleOnceAndOnlyPolicyOrMetadataChangesRetryNoMatch() throws {
        let track = song()
        XCTAssertTrue(CoverSearchHistory.isEligible(track))
        try CoverSearchHistory.write(.notFound, to: track)
        XCTAssertFalse(CoverSearchHistory.isEligible(track, now: Date().addingTimeInterval(100_000)))
        XCTAssertTrue(CoverSearchHistory.isEligible(track, revision: CoverSearchHistory.currentRevision + 1))
        track.title = "另一首歌曲"
        XCTAssertTrue(CoverSearchHistory.isEligible(track))
    }

    func testFailureBackoffAndInterruptionAreDifferentFromNoMatch() throws {
        let track = song()
        let now = Date(timeIntervalSince1970: 1_000)
        try CoverSearchHistory.write(.failed, to: track, now: now)
        XCTAssertFalse(CoverSearchHistory.isEligible(track, now: now.addingTimeInterval(59)))
        XCTAssertTrue(CoverSearchHistory.isEligible(track, now: now.addingTimeInterval(61)))
        try CoverSearchHistory.write(.searching, to: track, now: now)
        XCTAssertFalse(CoverSearchHistory.isEligible(track, now: now.addingTimeInterval(1_000)))
        try CoverSearchHistory.write(.failed, to: track, now: now)
        XCTAssertEqual(CoverSearchHistory.read(track)?.failures, 2)
        XCTAssertFalse(CoverSearchHistory.isEligible(track, now: now.addingTimeInterval(299)))
        try CoverSearchHistory.write(.pending, to: track, now: now)
        XCTAssertTrue(CoverSearchHistory.isEligible(track, now: now))
    }

    func testRealCoverAndUnavailableAudioNeverBecomeCandidates() throws {
        let track = song()
        track.artworkOriginRaw = CoverArtworkOrigin.manual.rawValue
        XCTAssertFalse(CoverSearchHistory.isEligible(track))
        track.artworkOriginRaw = CoverArtworkOrigin.generated.rawValue
        track.isAvailable = false
        XCTAssertFalse(CoverSearchHistory.isEligible(track))
    }

    func testHistoryAndOriginSurviveDiskReopenAndInterruptedSearchRecovers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([TrackRecord.self, PlaylistRecord.self, PlaylistEntryRecord.self, PlaybackPreferencesRecord.self])
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("history.store"))
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let store = try MusicStore(context: container.mainContext)
            let track = song()
            track.artworkOriginRaw = CoverArtworkOrigin.generated.rawValue
            try store.upsert(track)
            try store.saveCoverHistory(.notFound, track: track)
        }
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let store = try MusicStore(context: reopened.mainContext)
        let track = try XCTUnwrap(store.track(id: "history"))
        XCTAssertEqual(CoverSearchHistory.read(track)?.status, .notFound)
        XCTAssertEqual(CoverSearchHistory.origin(of: track), .generated)
        XCTAssertFalse(CoverSearchHistory.isEligible(track))
        try store.saveCoverHistory(.searching, track: track)
        try store.recoverInterruptedCoverSearches()
        XCTAssertEqual(CoverSearchHistory.read(track)?.status, .pending)
        XCTAssertTrue(CoverSearchHistory.isEligible(track))
    }
}
