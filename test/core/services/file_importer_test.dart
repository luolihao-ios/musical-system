import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_music_player/core/models/track.dart';
import 'package:local_music_player/core/services/file_importer.dart';
import 'package:local_music_player/core/services/music_source_gateway.dart';

class _DeniedMusicSourceGateway implements MusicSourceGateway {
  @override
  Future<List<Track>> listDeviceTracks() async => const [];

  @override
  Future<MediaLibraryAccess> requestMediaLibraryAccess() async {
    return MediaLibraryAccess.denied;
  }
}

void main() {
  late Directory sourceDirectory;
  late Directory destinationDirectory;

  setUp(() async {
    sourceDirectory = await Directory.systemTemp.createTemp(
      'music-import-source',
    );
    destinationDirectory = await Directory.systemTemp.createTemp(
      'music-import-destination',
    );
  });

  tearDown(() async {
    await sourceDirectory.delete(recursive: true);
    await destinationDirectory.delete(recursive: true);
  });

  test('copies an imported audio file into app storage', () async {
    final source = File(
      '${sourceDirectory.path}${Platform.pathSeparator}song.mp3',
    );
    await source.writeAsBytes([1, 2, 3]);
    final importer = FileImporter(
      destinationDirectory: () async => destinationDirectory,
    );

    final track = await importer.importPath(source.path);

    expect(File(track.uri!).existsSync(), isTrue);
    expect(track.uri, isNot(source.path));
    expect(track.source, TrackSource.file);
  });

  test('file import remains available after media-library denial', () async {
    final gateway = _DeniedMusicSourceGateway();
    final importer = FileImporter(
      destinationDirectory: () async => destinationDirectory,
    );

    expect(
      await gateway.requestMediaLibraryAccess(),
      MediaLibraryAccess.denied,
    );
    expect(importer.isAvailable, isTrue);
  });
}
