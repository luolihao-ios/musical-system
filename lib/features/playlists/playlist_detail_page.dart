import 'package:flutter/material.dart';

import '../../core/models/playlist.dart';
import '../../core/models/track.dart';

class PlaylistDetailPage extends StatelessWidget {
  const PlaylistDetailPage({
    super.key,
    required this.playlist,
    required this.tracks,
    this.onPlay,
    this.onRemove,
  });

  final Playlist playlist;
  final List<Track> tracks;
  final ValueChanged<Track>? onPlay;
  final ValueChanged<Track>? onRemove;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(playlist.name)),
      body: ListView.builder(
        itemCount: tracks.length,
        itemBuilder: (context, index) {
          final track = tracks[index];
          return ListTile(
            title: Text(track.title),
            subtitle: Text(track.artist),
            onTap: () => onPlay?.call(track),
            trailing: onRemove == null
                ? null
                : IconButton(
                    tooltip: '从歌单移除',
                    onPressed: () => onRemove?.call(track),
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
          );
        },
      ),
    );
  }
}
