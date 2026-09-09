import Foundation
import XCTest
@testable import LocalMusicPlayer

@MainActor
final class SystemLibraryImporterTests: XCTestCase {
    func testGeneratesArtworkWhenSystemItemHasNoArtwork() async throws {
        let artworkDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        let generatedArtwork = Data("generated-system-artwork".utf8)
        let gateway = FakeMediaLibraryGateway(
            authorization: .authorized,
            items: [
                MediaLibraryItem(
                    persistentID: 42,
                    title: "夜航星",
                    artist: "测试歌手",
                    album: "测试专辑",
                    duration: 240,
                    assetURL: URL(fileURLWithPath: "/music/local.m4a"),
                    artworkData: nil
                )
            ]
        )
        let importer = SystemLibraryImporter(
            gateway: gateway,
            artworkDirectory: artworkDirectory,
            artworkGenerator: SystemFakeArtworkGenerator(
                data: generatedArtwork
            )
        )

        let result = try await importer.importAuthorizedItems()

        guard case let .imported(tracks) = result else {
            return XCTFail("Expected imported tracks.")
        }
        let artworkPath = try XCTUnwrap(tracks.first?.artworkReference)
        XCTAssertEqual(
            URL(fileURLWithPath: artworkPath).lastPathComponent,
            "media-42-generated.jpg"
        )
        XCTAssertEqual(
            try Data(contentsOf: URL(fileURLWithPath: artworkPath)),
            generatedArtwork
        )
    }

    func testDeniedAuthorizationReturnsRecoverableResult() async throws {
        let gateway = FakeMediaLibraryGateway(
            authorization: .denied,
            items: []
        )
        let importer = SystemLibraryImporter(gateway: gateway)

        let result = try await importer.importAuthorizedItems()

        guard case .permissionDenied = result else {
            return XCTFail("Expected permissionDenied.")
        }
        XCTAssertEqual(gateway.playableItemsCallCount, 0)
    }

    func testImportsOnlyPlayableItemsWithStableIDsAndMetadata() async throws {
        let localURL = URL(fileURLWithPath: "/music/local.m4a")
        let gateway = FakeMediaLibraryGateway(
            authorization: .authorized,
            items: [
                MediaLibraryItem(
                    persistentID: 42,
                    title: "夜航星",
                    artist: "测试歌手",
                    album: "测试专辑",
                    duration: 240,
                    assetURL: localURL,
                    artworkData: nil
                ),
                MediaLibraryItem(
                    persistentID: 43,
                    title: "云端歌曲",
                    artist: "",
                    album: "",
                    duration: 180,
                    assetURL: nil,
                    artworkData: nil
                )
            ]
        )
        let importer = SystemLibraryImporter(gateway: gateway)

        let result = try await importer.importAuthorizedItems()

        guard case let .imported(tracks) = result else {
            return XCTFail("Expected imported tracks.")
        }
        XCTAssertEqual(tracks.map(\.id), ["media-42"])
        XCTAssertEqual(tracks[0].title, "夜航星")
        XCTAssertEqual(tracks[0].artist, "测试歌手")
        XCTAssertEqual(tracks[0].sourceReference, localURL.absoluteString)
        XCTAssertEqual(tracks[0].sourceKind, .mediaLibrary)
    }
}

@MainActor
private struct SystemFakeArtworkGenerator: ImportedArtworkGenerating {
    let data: Data

    func generateArtwork(
        title: String,
        artist: String,
        seed: String
    ) throws -> Data {
        data
    }
}

@MainActor
private final class FakeMediaLibraryGateway: MediaLibraryGateway {
    let authorization: MediaLibraryAuthorization
    let items: [MediaLibraryItem]
    private(set) var playableItemsCallCount = 0

    init(
        authorization: MediaLibraryAuthorization,
        items: [MediaLibraryItem]
    ) {
        self.authorization = authorization
        self.items = items
    }

    func requestAuthorization() async -> MediaLibraryAuthorization {
        authorization
    }

    func playableItems() -> [MediaLibraryItem] {
        playableItemsCallCount += 1
        return items
    }
}
