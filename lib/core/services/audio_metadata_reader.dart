import 'dart:io';

import 'package:metadata_god/metadata_god.dart' as metadata_god;

class AudioMetadata {
  const AudioMetadata({
    this.title,
    this.artist,
    this.album,
    this.duration = Duration.zero,
  });

  final String? title;
  final String? artist;
  final String? album;
  final Duration duration;
}

abstract interface class AudioMetadataReader {
  Future<AudioMetadata> read(File file);
}

class MetadataGodAudioMetadataReader implements AudioMetadataReader {
  Future<void>? _initialization;

  @override
  Future<AudioMetadata> read(File file) async {
    await (_initialization ??= metadata_god.MetadataGod.initialize());
    final metadata = await metadata_god.MetadataGod.readMetadata(
      file: file.path,
    );
    return AudioMetadata(
      title: metadata.title,
      artist: metadata.artist,
      album: metadata.album,
      duration: metadata.duration ?? Duration.zero,
    );
  }
}
