import Foundation
import Observation
import SwiftData

@MainActor
final class AppContainer {
    let modelContainer: ModelContainer
    let store: MusicStore
    let playback: PlaybackController
    let libraryModel: LibraryModel
    let playlistsModel: PlaylistsModel
    let nowPlayingModel: NowPlayingModel
    let transferHandoffImporter: TransferHandoffImporter

    private let nowPlayingBridge: NowPlayingBridge

    init(inMemory: Bool = false) throws {
        let modelContainer = try ModelContainerFactory.make(inMemory: inMemory)
        let store = try MusicStore(context: modelContainer.mainContext)
        let playback = PlaybackController(
            preferencesStore: store
        )
        try store.refreshAvailability()
        try store.recoverInterruptedCoverSearches()
        try playback.initialize()
        let libraryModel = LibraryModel(
            store: store,
            fileImporter: FileImportService(),
            systemImporter: SystemLibraryImporter(),
            playback: playback,
            scansAuthorizedFolders: !inMemory,
            coverSearch: inMemory ? nil : CatalogCoverSearch.shared,
            enablesAutoContinue: !inMemory
        )
        if !inMemory {
            playback.onAutoSkipNotice = { message in
                ToastCenter.shared.show(message, systemImage: "forward.end.fill")
            }
            playback.onTrackSessionEnded = { track, played, duration, wasManualSkip in
                TasteProfileStore.shared.recordPlaybackOutcome(
                    trackID: track.id,
                    artist: track.artist,
                    playedSeconds: played,
                    duration: duration,
                    wasManualSkip: wasManualSkip
                )
            }
        }
        CoverSearchDiagnostics.log("session version=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "?") build=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "?") provider=existing-catalogs")
        let playlistsModel = PlaylistsModel(
            store: store,
            playback: playback
        )
        try libraryModel.reload()
        if !inMemory {
            TasteProfileStore.shared.seedFromLocalLibrary(libraryModel.tracks)
        }
        try playlistsModel.reload()
        try playback.restoreQueueIfPossible(libraryModel.tracks)
        let bridge = NowPlayingBridge(controller: playback)
        let nowPlayingModel = NowPlayingModel(
            playback: playback,
            online: OnlineMusicResources.shared,
            store: store,
            tasteProfile: inMemory ? nil : TasteProfileStore.shared
        )

        self.modelContainer = modelContainer
        self.store = store
        self.playback = playback
        self.nowPlayingBridge = bridge
        self.libraryModel = libraryModel
        self.playlistsModel = playlistsModel
        self.nowPlayingModel = nowPlayingModel
        self.transferHandoffImporter = TransferHandoffImporter(importer: FileImportService(), store: store)
        if !inMemory { libraryModel.scheduleMissingCoverSearch() }
    }
}

@MainActor
@Observable
final class AppBootstrap {
    private(set) var container: AppContainer?
    private(set) var errorMessage: String?
    private var didStart = false

    func start() {
        guard !didStart else { return }
        didStart = true
        CrashExceptionDiagnostics.install()
        do {
            container = try AppContainer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
