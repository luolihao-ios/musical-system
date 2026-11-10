import AVFoundation
import XCTest
@testable import LocalMusicPlayer

@MainActor
final class DiscoveryModelTests: XCTestCase {
    func testFiltersUnplayableAndDuplicateTracksBeforeFillingLimit() {
        let valid = (0..<15).map { song("track-\($0)") }
        let missing = CatalogTrack(id: "metadata-only", title: "No audio", artist: "Artist",
                                   audioURL: URL(string: "https://example.invalid")!, license: .unknown)
        let insecure = song("insecure", url: "http://example.org/song.mp3")
        let badHost = song("bad-host", url: "https://example.invalid/song.mp3")
        let picks = DiscoveryModel.playableTracks([missing, insecure, badHost, valid[0]] + valid)
        XCTAssertEqual(picks.map(\.id), Array(valid.prefix(12)).map(\.id))
    }

    func testRegionalQueriesAreIndependentOfLocalMusic() {
        let cn = DiscoveryMarket(locale: Locale(identifier: "zh_CN"))
        let fr = DiscoveryMarket(locale: Locale(identifier: "fr_FR"))
        XCTAssertEqual(cn.regionalQuery, "轻音乐")
        XCTAssertEqual(fr.openQuery, "chanson")
        XCTAssertNotEqual(cn.region, fr.region)
    }

    func testFailedRefreshRetainsCachedOnlineTracksAndKeepsMarketsSeparate() async throws {
        let suite = "DiscoveryModelTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cn = DiscoveryMarket(locale: Locale(identifier: "zh_CN"))
        let expected = song("online-pick")
        let initial = DiscoveryModel(market: cn, defaults: defaults) { _ in [expected] }
        await initial.loadIfNeeded()
        let offline = DiscoveryModel(market: cn, defaults: defaults) { _ in throw URLError(.notConnectedToInternet) }
        XCTAssertEqual(offline.tracks, [expected])
        await offline.refresh()
        XCTAssertEqual(offline.tracks, [expected])
        XCTAssertTrue(offline.isUnavailable)
        let fr = DiscoveryModel(market: .init(locale: Locale(identifier: "fr_FR")), defaults: defaults)
        XCTAssertTrue(fr.tracks.isEmpty)
    }

    func testImportThroughExistingLibraryDoesNotReplaceHomepagePicks() async throws {
        let suite = "DiscoveryModelTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let recommendation = song("online-pick")
        let home = DiscoveryModel(defaults: defaults) { _ in [recommendation] }
        await home.loadIfNeeded()

        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let audio = temporary.appendingPathComponent("Import isolation.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2205))
        buffer.frameLength = 2205
        buffer.floatChannelData?[0].initialize(repeating: 0, count: Int(buffer.frameLength))
        do {
            let file = try AVAudioFile(forWriting: audio, settings: format.settings)
            try file.write(from: buffer)
        }

        let container = try AppContainer(inMemory: true)
        let library = LibraryModel(store: container.store,
            fileImporter: FileImportService(rootDirectory: temporary.appendingPathComponent("imported")),
            systemImporter: SystemLibraryImporter(), playback: container.playback)
        XCTAssertTrue(library.tracks.isEmpty)
        await library.importFiles([ImportedFile(sourceURL: audio, kind: .audio)])
        XCTAssertEqual(library.tracks.count, 1)
        XCTAssertEqual(home.tracks, [recommendation])
        await home.loadIfNeeded()
        XCTAssertEqual(home.tracks, [recommendation])
    }

    private func song(_ id: String, url: String = "https://example.org/song.mp3") -> CatalogTrack {
        let address = URL(string: url)!
        return CatalogTrack(id: id, title: "Online track", artist: "Artist",
                            audioURL: address, license: .unknown, previewURL: address)
    }
}
