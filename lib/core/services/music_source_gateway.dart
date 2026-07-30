import 'dart:io';

import 'package:flutter/services.dart';

import '../models/track.dart';

enum MediaLibraryAccess { notDetermined, denied, restricted, authorized }

abstract interface class MusicSourceGateway {
  Future<MediaLibraryAccess> requestMediaLibraryAccess();
  Future<List<Track>> listDeviceTracks();
}

class IosMusicSourceGateway implements MusicSourceGateway {
  const IosMusicSourceGateway();

  static const _channel = MethodChannel('local_music_player/media_library');

  @override
  Future<MediaLibraryAccess> requestMediaLibraryAccess() async {
    if (!Platform.isIOS) {
      return MediaLibraryAccess.restricted;
    }
    final value = await _channel.invokeMethod<String>('requestAccess');
    return MediaLibraryAccess.values.firstWhere(
      (status) => status.name == value,
      orElse: () => MediaLibraryAccess.restricted,
    );
  }

  @override
  Future<List<Track>> listDeviceTracks() async {
    if (!Platform.isIOS) {
      return const [];
    }
    final rows =
        await _channel.invokeListMethod<Map<Object?, Object?>>('listTracks') ??
        const [];
    return rows
        .map((row) {
          final id = row['id']?.toString() ?? '';
          return Track(
            id: 'ios:$id',
            title: row['title']?.toString() ?? '未知歌曲',
            artist: row['artist']?.toString() ?? '未知歌手',
            album: row['album']?.toString(),
            uri: row['uri']?.toString(),
            duration: Duration(
              milliseconds: (row['durationMs'] as num?)?.round() ?? 0,
            ),
            source: TrackSource.iosMediaLibrary,
          );
        })
        .toList(growable: false);
  }
}
