import 'dart:io';

import '../models/track.dart';
import 'audio_metadata_reader.dart';
import 'lyrics_locator.dart';

class ScanResult {
  const ScanResult({required this.tracks, required this.skippedCount});

  final List<Track> tracks;
  final int skippedCount;

  int get indexedCount => tracks.length;
}

class MusicScanner {
  factory MusicScanner({
    required AudioMetadataReader metadataReader,
    required LyricsLocator lyricsLocator,
  }) {
    return MusicScanner._(metadataReader, lyricsLocator);
  }

  MusicScanner._(this._metadataReader, this._lyricsLocator);

  static const supportedExtensions = {
    '.mp3',
    '.m4a',
    '.aac',
    '.flac',
    '.wav',
    '.ogg',
  };

  final AudioMetadataReader _metadataReader;
  final LyricsLocator _lyricsLocator;

  Future<ScanResult> scanDirectory(Directory root) async {
    final tracks = <Track>[];
    var skippedCount = 0;
    await for (final entry in root.list(recursive: true, followLinks: false)) {
      if (entry is! File || !_isSupported(entry.path)) {
        continue;
      }
      try {
        final metadata = await _metadataReader.read(entry);
        final lyrics = await _lyricsLocator.findForAudio(entry);
        tracks.add(
          Track(
            id: _stableFileId(entry),
            title: _nonBlank(metadata.title) ?? _fileStem(entry.path),
            artist: _nonBlank(metadata.artist) ?? '未知歌手',
            album: _nonBlank(metadata.album),
            source: TrackSource.file,
            uri: entry.path,
            duration: metadata.duration,
            lyricPath: lyrics?.path,
          ),
        );
      } on Object {
        skippedCount += 1;
      }
    }
    tracks.sort((left, right) => left.title.compareTo(right.title));
    return ScanResult(tracks: tracks, skippedCount: skippedCount);
  }

  bool isAvailable(Track track) {
    return track.source != TrackSource.file ||
        (track.uri != null && File(track.uri!).existsSync());
  }

  bool _isSupported(String path) {
    final normalized = path.toLowerCase();
    return supportedExtensions.any(normalized.endsWith);
  }

  String _stableFileId(File file) {
    final normalized = file.absolute.path.replaceAll('\\', '/').toLowerCase();
    return 'file:$normalized';
  }

  String _fileStem(String path) {
    final separator = Platform.pathSeparator;
    final start = path.lastIndexOf(separator) + 1;
    final end = path.lastIndexOf('.');
    return path.substring(start, end > start ? end : path.length);
  }

  String? _nonBlank(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
