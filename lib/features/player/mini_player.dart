import 'package:flutter/material.dart';

import '../../core/models/playback_state.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    super.key,
    required this.snapshot,
    required this.onOpen,
    required this.onPlayPause,
    required this.onNext,
  });

  final PlaybackSnapshot snapshot;
  final VoidCallback onOpen;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final track = snapshot.currentTrack;
    if (track == null) return const SizedBox.shrink();
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: InkWell(
        onTap: onOpen,
        child: SizedBox(
          height: 76,
          child: Row(
            children: [
              const SizedBox(width: 14),
              const CircleAvatar(
                radius: 24,
                backgroundColor: Color(0xFFE5484D),
                child: Icon(Icons.music_note_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: snapshot.isPlaying ? '暂停' : '播放',
                onPressed: onPlayPause,
                icon: Icon(
                  snapshot.isPlaying
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_fill_rounded,
                  size: 34,
                ),
              ),
              IconButton(
                tooltip: '下一首',
                onPressed: onNext,
                icon: const Icon(Icons.skip_next_rounded),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}
