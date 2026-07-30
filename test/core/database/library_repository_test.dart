import 'package:flutter_test/flutter_test.dart';
import 'package:local_music_player/core/database/app_database.dart';
import 'package:local_music_player/core/database/library_repository.dart';
import 'package:local_music_player/core/models/track.dart';

void main() {
  late AppDatabase database;
  late LibraryRepository repository;

  setUp(() {
    database = AppDatabase.inMemory();
    repository = LibraryRepository(database);
  });

  tearDown(() => database.close());

  test('liked tracks persist and are returned', () async {
    const track = Track(id: 'track-a', title: '晨光', source: TrackSource.file);

    await repository.upsertTrack(track);
    await repository.toggleLike(track.id);

    expect((await repository.likedTracks()).single.id, track.id);
  });

  test('the built-in liked playlist cannot be deleted', () async {
    expect(
      () => repository.deletePlaylist(LibraryRepository.likedPlaylistId),
      throwsA(isA<StateError>()),
    );
  });
}
