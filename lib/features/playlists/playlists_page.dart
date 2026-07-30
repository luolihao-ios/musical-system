import 'package:flutter/material.dart';

import '../../core/models/playlist.dart';

class PlaylistsPage extends StatelessWidget {
  const PlaylistsPage({
    super.key,
    required this.playlists,
    this.onCreate,
    this.onOpen,
    this.onDelete,
  });

  final List<Playlist> playlists;
  final VoidCallback? onCreate;
  final ValueChanged<Playlist>? onOpen;
  final ValueChanged<Playlist>? onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '我的歌单',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton(
                tooltip: '新建歌单',
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final playlist in playlists)
            ListTile(
              leading: Icon(
                playlist.isBuiltIn
                    ? Icons.favorite_rounded
                    : Icons.queue_music_rounded,
              ),
              title: Text(playlist.name),
              onTap: () => onOpen?.call(playlist),
              trailing: playlist.isBuiltIn
                  ? null
                  : IconButton(
                      tooltip: '删除歌单',
                      onPressed: () => onDelete?.call(playlist),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
            ),
        ],
      ),
    );
  }
}
