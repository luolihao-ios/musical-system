import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/playback_state.dart';
import '../models/track.dart';

abstract interface class PlaybackEngine {
  Stream<void> get completionEvents;
  Future<void> load(String uri);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> dispose();
}

class JustAudioPlaybackEngine implements PlaybackEngine {
  JustAudioPlaybackEngine({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<void> get completionEvents => _player.playerStateStream
      .where((state) => state.processingState == ProcessingState.completed)
      .map((_) {});

  @override
  Future<void> load(String uri) async {
    final parsed = Uri.tryParse(uri);
    if (parsed != null && parsed.hasScheme) {
      await _player.setUrl(uri);
    } else {
      await _player.setFilePath(uri);
    }
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> dispose() => _player.dispose();
}

class PlaybackController {
  PlaybackController(PlaybackEngine engine)
    : _engine = engine,
      state = ValueNotifier(const PlaybackSnapshot()) {
    _completionSubscription = _engine.completionEvents.listen((_) {
      unawaited(_handleCompletion());
    });
  }

  final PlaybackEngine _engine;
  final ValueNotifier<PlaybackSnapshot> state;
  final Random _random = Random();
  late final StreamSubscription<void> _completionSubscription;

  PlaybackSnapshot get value => state.value;

  void setQueue(List<Track> tracks) {
    final immutable = List<Track>.unmodifiable(tracks);
    final currentId = value.currentTrack?.id;
    final retainedIndex = immutable.indexWhere(
      (track) => track.id == currentId,
    );
    state.value = value.copyWith(queue: immutable, currentIndex: retainedIndex);
  }

  Future<void> playTrack(Track track) async {
    final uri = track.uri;
    if (uri == null || uri.isEmpty) {
      throw StateError('歌曲没有可播放的本地地址');
    }
    var index = value.queue.indexWhere((item) => item.id == track.id);
    if (index < 0) {
      final queue = [...value.queue, track];
      index = queue.length - 1;
      state.value = value.copyWith(queue: List.unmodifiable(queue));
    }
    await _engine.load(uri);
    await _engine.play();
    state.value = value.copyWith(
      currentIndex: index,
      isPlaying: true,
      position: Duration.zero,
    );
  }

  Future<void> play() async {
    if (value.currentTrack == null) return;
    await _engine.play();
    state.value = value.copyWith(isPlaying: true);
  }

  Future<void> pause() async {
    await _engine.pause();
    state.value = value.copyWith(isPlaying: false);
  }

  Future<void> seek(Duration position) async {
    await _engine.seek(position);
    state.value = value.copyWith(position: position);
  }

  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0);
    await _engine.setVolume(clamped);
    state.value = value.copyWith(volume: clamped);
  }

  void setMode(PlayMode mode) {
    state.value = value.copyWith(mode: mode);
  }

  void toggleShuffle() {
    setMode(
      value.mode == PlayMode.shuffle ? PlayMode.sequential : PlayMode.shuffle,
    );
  }

  Future<void> next() async {
    if (value.queue.isEmpty) return;
    final nextIndex = _nextIndex();
    if (nextIndex == null) {
      await pause();
      return;
    }
    await playTrack(value.queue[nextIndex]);
  }

  Future<void> previous() async {
    if (value.queue.isEmpty) return;
    final previousIndex = value.currentIndex <= 0
        ? (value.mode == PlayMode.allLoop ? value.queue.length - 1 : 0)
        : value.currentIndex - 1;
    await playTrack(value.queue[previousIndex]);
  }

  Future<void> _handleCompletion() async {
    if (value.mode == PlayMode.singleLoop) {
      await _engine.seek(Duration.zero);
      await _engine.play();
      state.value = value.copyWith(isPlaying: true, position: Duration.zero);
      return;
    }
    await next();
  }

  int? _nextIndex() {
    if (value.mode == PlayMode.shuffle && value.queue.length > 1) {
      var next = value.currentIndex;
      while (next == value.currentIndex) {
        next = _random.nextInt(value.queue.length);
      }
      return next;
    }
    final candidate = value.currentIndex + 1;
    if (candidate < value.queue.length) return candidate;
    return value.mode == PlayMode.allLoop ? 0 : null;
  }

  Future<void> dispose() async {
    await _completionSubscription.cancel();
    await _engine.dispose();
    state.dispose();
  }
}
