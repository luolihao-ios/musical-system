import 'package:drift/drift.dart';

import '../models/playlist.dart' as domain;
import '../models/track.dart';
import 'app_database.dart';

class LibraryRepository {
  LibraryRepository(this._database);

  static const likedPlaylistId = 'liked';

  final AppDatabase _database;

  Future<void> upsertTrack(Track track) async {
    await _database
        .into(_database.tracks)
        .insertOnConflictUpdate(
          TracksCompanion.insert(
            id: track.id,
            title: track.title,
            artist: Value(track.artist),
            album: Value(track.album),
            uri: Value(track.uri),
            source: track.source.index,
            durationMs: Value(track.duration.inMilliseconds),
            artworkPath: Value(track.artworkPath),
            lyricPath: Value(track.lyricPath),
            isLiked: Value(track.isLiked),
            importedAt: Value(track.importedAt ?? DateTime.now()),
            lastPlayedAt: Value(track.lastPlayedAt),
          ),
        );
  }

  Future<void> toggleLike(String trackId) async {
    final record = await (_database.select(
      _database.tracks,
    )..where((row) => row.id.equals(trackId))).getSingle();
    await (_database.update(_database.tracks)
          ..where((row) => row.id.equals(trackId)))
        .write(TracksCompanion(isLiked: Value(!record.isLiked)));
  }

  Future<List<Track>> likedTracks() async {
    final query = _database.select(_database.tracks)
      ..where((row) => row.isLiked.equals(true))
      ..orderBy([
        (row) =>
            OrderingTerm(expression: row.lastPlayedAt, mode: OrderingMode.desc),
      ]);
    return (await query.get()).map(_toTrack).toList(growable: false);
  }

  Future<domain.Playlist> createPlaylist(String name) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    await _database
        .into(_database.playlists)
        .insert(PlaylistsCompanion.insert(id: id, name: name));
    return domain.Playlist(id: id, name: name);
  }

  Future<void> deletePlaylist(String playlistId) async {
    if (playlistId == likedPlaylistId) {
      throw StateError('内置歌单“我喜欢”不能删除');
    }
    await (_database.delete(
      _database.playlists,
    )..where((row) => row.id.equals(playlistId))).go();
  }

  Track _toTrack(TrackRecord row) {
    return Track(
      id: row.id,
      title: row.title,
      artist: row.artist,
      album: row.album,
      uri: row.uri,
      source: TrackSource.values[row.source],
      duration: Duration(milliseconds: row.durationMs),
      artworkPath: row.artworkPath,
      lyricPath: row.lyricPath,
      isLiked: row.isLiked,
      importedAt: row.importedAt,
      lastPlayedAt: row.lastPlayedAt,
    );
  }
}
