import Foundation
import Observation

struct PlaylistSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let isBuiltIn: Bool

    @MainActor
    init(_ record: PlaylistRecord) {
        id = record.id
        name = record.name
        isBuiltIn = record.isBuiltIn
    }
}

@MainActor
@Observable
final class PlaylistsModel {
    private(set) var playlists: [PlaylistSnapshot] = []
    var selectedPlaylistID: String?

    private let store: MusicStore
    private let playback: (any LibraryPlaybackControlling)?

    init(
        store: MusicStore,
        playback: (any LibraryPlaybackControlling)? = nil
    ) {
        self.store = store
        self.playback = playback
    }

    func reload() throws {
        playlists = try store.playlists().map(PlaylistSnapshot.init)
        if selectedPlaylistID == nil {
            selectedPlaylistID = playlists.first?.id
        }
    }

    @discardableResult
    func create(name: String) throws -> PlaylistSnapshot {
        let playlist = try store.createPlaylist(name: name)
        try reload()
        selectedPlaylistID = playlist.id
        return PlaylistSnapshot(playlist)
    }

    @discardableResult
    func rename(
        _ playlist: PlaylistSnapshot,
        to name: String
    ) throws -> Bool {
        let result = try store.renamePlaylist(id: playlist.id, name: name)
        try reload()
        return result
    }

    @discardableResult
    func delete(_ playlist: PlaylistSnapshot) throws -> Bool {
        let result = try store.deletePlaylist(id: playlist.id)
        try reload()
        return result
    }

    func tracks(in playlist: PlaylistSnapshot) throws -> [TrackSnapshot] {
        try store.playlistTracks(playlistID: playlist.id).map(TrackSnapshot.init)
    }

    func add(trackID: String, to playlistID: String) throws {
        try store.add(trackID: trackID, to: playlistID)
    }

    func remove(trackID: String, from playlistID: String) throws {
        try store.remove(trackID: trackID, from: playlistID)
    }

    func play(
        _ track: TrackSnapshot,
        in playlist: PlaylistSnapshot
    ) async throws {
        guard let playback else { return }
        let queue = try tracks(in: playlist).filter(\.isAvailable)
        guard let index = queue.firstIndex(where: { $0.id == track.id }) else {
            return
        }
        try playback.loadQueue(queue, startIndex: index)
        try await playback.play()
        try store.recordPlay(trackID: track.id)
    }
}
