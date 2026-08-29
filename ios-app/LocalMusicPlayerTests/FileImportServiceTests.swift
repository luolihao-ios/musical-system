import Foundation
import XCTest
@testable import LocalMusicPlayer

@MainActor
final class FileImportServiceTests: XCTestCase {
    func testImportsSupportedAudioWithMatchingLyricsAndFilenameFallback() async throws {
        let fixture = try Fixture()
        let audio = try fixture.file(name: "夜航星.MP3", contents: Data("audio".utf8))
        let lyrics = try fixture.file(
            name: "夜航星.lrc",
            contents: Data("[00:01.00]第一句".utf8)
        )
        let security = FakeSecurityScope()
        let service = FileImportService(
            rootDirectory: fixture.importRoot,
            metadataReader: FakeMetadataReader(
                metadata: ImportedMetadata(
                    title: "",
                    artist: "测试歌手",
                    album: "测试专辑",
                    duration: 180,
                    artworkData: Data([1, 2, 3])
                )
            ),
            securityScope: security
        )

        let tracks = try await service.importFiles([
            ImportedFile(sourceURL: audio, kind: .audio),
            ImportedFile(sourceURL: lyrics, kind: .lyrics)
        ])

        let track = try XCTUnwrap(tracks.first)
        XCTAssertEqual(track.title, "夜航星")
        XCTAssertEqual(track.artist, "测试歌手")
        XCTAssertTrue(FileManager.default.fileExists(atPath: track.sourceReference))
        XCTAssertNotNil(track.lyricsReference)
        XCTAssertNotNil(track.artworkReference)
        XCTAssertEqual(security.beginCount, security.endCount)
    }

    func testSameSourceNameWithDifferentContentUsesUniqueSandboxDirectories() async throws {
        let fixture = try Fixture()
        let firstFolder = fixture.root.appending(path: "first")
        let secondFolder = fixture.root.appending(path: "second")
        try FileManager.default.createDirectory(
            at: firstFolder,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: secondFolder,
            withIntermediateDirectories: true
        )
        let first = firstFolder.appending(path: "song.m4a")
        let second = secondFolder.appending(path: "song.m4a")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        let service = FileImportService(
            rootDirectory: fixture.importRoot,
            metadataReader: FakeMetadataReader(
                metadata: ImportedMetadata(
                    title: "歌曲",
                    artist: "",
                    album: "",
                    duration: 1,
                    artworkData: nil
                )
            )
        )

        let tracks = try await service.importFiles([
            ImportedFile(sourceURL: first, kind: .audio),
            ImportedFile(sourceURL: second, kind: .audio)
        ])

        XCTAssertEqual(Set(tracks.map(\.id)).count, 2)
        XCTAssertNotEqual(
            URL(fileURLWithPath: tracks[0].sourceReference).deletingLastPathComponent(),
            URL(fileURLWithPath: tracks[1].sourceReference).deletingLastPathComponent()
        )
    }

    func testFilenameFallbackSeparatesTitleAndArtistAtLastHyphen() async throws {
        let fixture = try Fixture()
        let audio = try fixture.file(
            name: "明天你好 (Live)-薛之谦,李玉刚.mp3",
            contents: Data("audio".utf8)
        )
        let service = FileImportService(
            rootDirectory: fixture.importRoot,
            metadataReader: FakeMetadataReader(
                metadata: ImportedMetadata(
                    title: "",
                    artist: "",
                    album: "",
                    duration: 180,
                    artworkData: nil
                )
            )
        )

        let tracks = try await service.importFiles([
            ImportedFile(sourceURL: audio, kind: .audio)
        ])
        let track = try XCTUnwrap(tracks.first)

        XCTAssertEqual(track.title, "明天你好 (Live)")
        XCTAssertEqual(track.artist, "薛之谦,李玉刚")
    }

    func testEmbeddedMetadataTakesPriorityOverHyphenatedFilename() async throws {
        let fixture = try Fixture()
        let audio = try fixture.file(
            name: "文件标题-文件歌手.m4a",
            contents: Data("audio".utf8)
        )
        let service = FileImportService(
            rootDirectory: fixture.importRoot,
            metadataReader: FakeMetadataReader(
                metadata: ImportedMetadata(
                    title: "元数据标题",
                    artist: "元数据歌手",
                    album: "元数据专辑",
                    duration: 180,
                    artworkData: nil
                )
            )
        )

        let tracks = try await service.importFiles([
            ImportedFile(sourceURL: audio, kind: .audio)
        ])
        let track = try XCTUnwrap(tracks.first)

        XCTAssertEqual(track.title, "元数据标题")
        XCTAssertEqual(track.artist, "元数据歌手")
        XCTAssertEqual(track.album, "元数据专辑")
    }

    func testOggIsRejectedAndInterruptedImportCleansStagingDirectory() async throws {
        let fixture = try Fixture()
        let ogg = try fixture.file(name: "unsupported.ogg", contents: Data("ogg".utf8))
        let failingAudio = try fixture.file(name: "broken.wav", contents: Data("wav".utf8))
        let security = FakeSecurityScope()
        let service = FileImportService(
            rootDirectory: fixture.importRoot,
            metadataReader: FailingMetadataReader(),
            securityScope: security
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await service.importFiles([
                ImportedFile(sourceURL: ogg, kind: .audio)
            ])
        }
        await XCTAssertThrowsErrorAsync {
            _ = try await service.importFiles([
                ImportedFile(sourceURL: failingAudio, kind: .audio)
            ])
        }

        let entries = try FileManager.default.contentsOfDirectory(
            at: fixture.importRoot,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(entries.allSatisfy { !$0.lastPathComponent.contains(".staging-") })
        XCTAssertEqual(security.beginCount, security.endCount)
    }
}

private struct FakeMetadataReader: ImportedMetadataReading {
    let metadata: ImportedMetadata

    func read(_ url: URL) async throws -> ImportedMetadata {
        metadata
    }
}

private struct FailingMetadataReader: ImportedMetadataReading {
    struct Failure: Error {}

    func read(_ url: URL) async throws -> ImportedMetadata {
        throw Failure()
    }
}

@MainActor
private final class FakeSecurityScope: SecurityScopedAccessing {
    private(set) var beginCount = 0
    private(set) var endCount = 0

    func beginAccessing(_ url: URL) -> Bool {
        beginCount += 1
        return true
    }

    func endAccessing(_ url: URL) {
        endCount += 1
    }
}

private struct Fixture {
    let root: URL
    let importRoot: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "LocalMusicPlayerTests")
            .appending(path: UUID().uuidString)
        importRoot = root.appending(path: "ImportedMusic")
        try FileManager.default.createDirectory(
            at: importRoot,
            withIntermediateDirectories: true
        )
    }

    func file(name: String, contents: Data) throws -> URL {
        let url = root.appending(path: name)
        try contents.write(to: url)
        return url
    }
}

@MainActor
private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected expression to throw.", file: file, line: line)
    } catch {
    }
}
