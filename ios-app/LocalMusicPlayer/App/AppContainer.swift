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
        try playback.initialize()
        let bridge = NowPlayingBridge(controller: playback)
        let libraryModel = LibraryModel(
            store: store,
            fileImporter: FileImportService(),
            systemImporter: SystemLibraryImporter(),
            playback: playback
        )
        let playlistsModel = PlaylistsModel(
            store: store,
            playback: playback
        )
        let nowPlayingModel = NowPlayingModel(playback: playback)
        try libraryModel.reload()
        try playlistsModel.reload()

        self.modelContainer = modelContainer
        self.store = store
        self.playback = playback
        self.nowPlayingBridge = bridge
        self.libraryModel = libraryModel
        self.playlistsModel = playlistsModel
        self.nowPlayingModel = nowPlayingModel
        self.transferHandoffImporter = TransferHandoffImporter(importer: FileImportService(), store: store)
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
        do {
            container = try AppContainer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
