import 'package:flutter/material.dart';

import '../../core/models/lyric_line.dart';
import '../../core/models/playback_state.dart';
import '../../core/services/playback_controller.dart';
import 'no_lyrics_visual.dart';
import 'synced_lyrics.dart';

class NowPlayingPage extends StatelessWidget {
  const NowPlayingPage({
    super.key,
    required this.controller,
    this.lyrics = const [],
  });

  final PlaybackController controller;
  final List<LyricLine> lyrics;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaybackSnapshot>(
      valueListenable: controller.state,
      builder: (context, snapshot, _) {
        final track = snapshot.currentTrack;
        return Scaffold(
          appBar: AppBar(backgroundColor: Colors.transparent),
          extendBodyBehindAppBar: true,
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF431B23),
                  Color(0xFF17171B),
                  Color(0xFF09090B),
                ],
              ),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 760;
                  final visual = Center(
                    child: lyrics.isEmpty
                        ? const NoLyricsVisual()
                        : SyncedLyrics(
                            position: snapshot.position,
                            lines: lyrics,
                          ),
                  );
                  final controls = _PlayerControls(
                    snapshot: snapshot,
                    onPlayPause: snapshot.isPlaying
                        ? controller.pause
                        : controller.play,
                    onNext: controller.next,
                    onPrevious: controller.previous,
                    onSeek: controller.seek,
                    onMode: controller.setMode,
                  );
                  if (wide) {
                    return Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(child: visual),
                              controls,
                            ],
                          ),
                        ),
                        if (lyrics.isNotEmpty)
                          Expanded(
                            child: SyncedLyrics(
                              position: snapshot.position,
                              lines: lyrics,
                            ),
                          ),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Expanded(child: visual),
                      if (track != null) ...[
                        Text(
                          track.title,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Text(
                          track.artist,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                      controls,
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlayerControls extends StatelessWidget {
  const _PlayerControls({
    required this.snapshot,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onSeek,
    required this.onMode,
  });

  final PlaybackSnapshot snapshot;
  final Future<void> Function() onPlayPause;
  final Future<void> Function() onNext;
  final Future<void> Function() onPrevious;
  final Future<void> Function(Duration) onSeek;
  final ValueChanged<PlayMode> onMode;

  @override
  Widget build(BuildContext context) {
    final duration = snapshot.currentTrack?.duration ?? Duration.zero;
    final maximum = duration.inMilliseconds <= 0
        ? 1.0
        : duration.inMilliseconds.toDouble();
    final value = snapshot.position.inMilliseconds
        .clamp(0, maximum.toInt())
        .toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
      child: Column(
        children: [
          Slider(
            value: value,
            max: maximum,
            onChanged: (position) =>
                onSeek(Duration(milliseconds: position.round())),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                tooltip: '播放模式',
                onPressed: () => onMode(
                  PlayMode.values[(snapshot.mode.index + 1) %
                      PlayMode.values.length],
                ),
                icon: Icon(
                  snapshot.mode == PlayMode.shuffle
                      ? Icons.shuffle_rounded
                      : snapshot.mode == PlayMode.singleLoop
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                ),
              ),
              IconButton(
                tooltip: '上一首',
                onPressed: onPrevious,
                icon: const Icon(Icons.skip_previous_rounded, size: 38),
              ),
              IconButton.filled(
                tooltip: snapshot.isPlaying ? '暂停' : '播放',
                onPressed: onPlayPause,
                icon: Icon(
                  snapshot.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 42,
                ),
              ),
              IconButton(
                tooltip: '下一首',
                onPressed: onNext,
                icon: const Icon(Icons.skip_next_rounded, size: 38),
              ),
              IconButton(
                tooltip: '播放队列',
                onPressed: () {},
                icon: const Icon(Icons.queue_music_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
