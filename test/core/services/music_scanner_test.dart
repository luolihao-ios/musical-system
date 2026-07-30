import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_music_player/core/services/audio_metadata_reader.dart';
import 'package:local_music_player/core/services/lyrics_locator.dart';
import 'package:local_music_player/core/services/music_scanner.dart';

class _FakeMetadataReader implements AudioMetadataReader {
  @override
  Future<AudioMetadata> read(File file) async {
    return const AudioMetadata(
      title: '晨光',
      artist: '林雨',
      duration: Duration(minutes: 3),
    );
  }
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('music-scanner-test');
  });

  tearDown(() async {
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  });

  test('indexes supported audio and finds an adjacent lrc', () async {
    final album = await Directory(
      '${root.path}${Platform.pathSeparator}album',
    ).create();
    await File(
      '${album.path}${Platform.pathSeparator}dawn.mp3',
    ).writeAsBytes([1, 2, 3]);
    await File(
      '${album.path}${Platform.pathSeparator}dawn.lrc',
    ).writeAsString('[00:01.00]晨光');
    await File(
      '${album.path}${Platform.pathSeparator}cover.txt',
    ).writeAsString('not audio');
    final scanner = MusicScanner(
      metadataReader: _FakeMetadataReader(),
      lyricsLocator: const LyricsLocator(),
    );

    final result = await scanner.scanDirectory(root);

    expect(result.indexedCount, 1);
    expect(result.tracks.single.title, '晨光');
    expect(result.tracks.single.lyricPath, endsWith('dawn.lrc'));
  });

  test('marks a discovered file unavailable after it is removed', () async {
    final audio = File('${root.path}${Platform.pathSeparator}missing.flac');
    await audio.writeAsBytes([1]);
    final scanner = MusicScanner(
      metadataReader: _FakeMetadataReader(),
      lyricsLocator: const LyricsLocator(),
    );
    final result = await scanner.scanDirectory(root);
    await audio.delete();

    expect(scanner.isAvailable(result.tracks.single), isFalse);
  });
}
