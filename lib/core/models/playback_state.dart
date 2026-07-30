import 'track.dart';

enum PlayMode { sequential, allLoop, singleLoop, shuffle }

class PlaybackSnapshot {
  const PlaybackSnapshot({
    this.queue = const [],
    this.currentIndex = -1,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.volume = 1,
    this.mode = PlayMode.sequential,
  });

  final List<Track> queue;
  final int currentIndex;
  final bool isPlaying;
  final Duration position;
  final double volume;
  final PlayMode mode;

  Track? get currentTrack => currentIndex >= 0 && currentIndex < queue.length
      ? queue[currentIndex]
      : null;

  PlaybackSnapshot copyWith({
    List<Track>? queue,
    int? currentIndex,
    bool? isPlaying,
    Duration? position,
    double? volume,
    PlayMode? mode,
  }) {
    return PlaybackSnapshot(
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      volume: volume ?? this.volume,
      mode: mode ?? this.mode,
    );
  }
}
