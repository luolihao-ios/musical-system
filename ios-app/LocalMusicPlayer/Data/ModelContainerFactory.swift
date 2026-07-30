import SwiftData

enum ModelContainerFactory {
    @MainActor
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            TrackRecord.self,
            PlaylistRecord.self,
            PlaylistEntryRecord.self,
            PlaybackPreferencesRecord.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
}
