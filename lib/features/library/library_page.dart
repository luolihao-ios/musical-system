import 'package:flutter/material.dart';

import '../../core/models/track.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.tracks,
    this.onPlay,
    this.onToggleLike,
    this.onImport,
  });

  final List<Track> tracks;
  final ValueChanged<Track>? onPlay;
  final ValueChanged<Track>? onToggleLike;
  final VoidCallback? onImport;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final normalized = _query.trim().toLowerCase();
    final visible = widget.tracks
        .where((track) {
          if (normalized.isEmpty) return true;
          return track.title.toLowerCase().contains(normalized) ||
              track.artist.toLowerCase().contains(normalized) ||
              (track.album?.toLowerCase().contains(normalized) ?? false);
        })
        .toList(growable: false);
    return Material(
      color: Colors.transparent,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 14),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '本地音乐',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: widget.onImport,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('导入本地音乐'),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverToBoxAdapter(
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  hintText: '搜索歌曲、歌手或专辑',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
          ),
          if (visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(widget.tracks.isEmpty ? '导入本地音乐' : '没有找到匹配的歌曲'),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              sliver: SliverList.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final track = visible[index];
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.music_note)),
                    title: Text(track.title),
                    subtitle: Text(
                      track.album == null
                          ? track.artist
                          : '${track.artist} · ${track.album}',
                    ),
                    onTap: () => widget.onPlay?.call(track),
                    trailing: IconButton(
                      tooltip: track.isLiked ? '取消喜欢' : '我喜欢',
                      onPressed: () => widget.onToggleLike?.call(track),
                      icon: Icon(
                        track.isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
