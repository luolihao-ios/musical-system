import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_music_player/core/models/playback_state.dart';
import 'package:local_music_player/core/models/track.dart';
import 'package:local_music_player/core/services/playback_controller.dart';
import 'package:local_music_player/core/services/system_media_handler.dart';

class _FakePlaybackEngine implements PlaybackEngine {
  final _completion = StreamController<void>.broadcast();
  final seekCalls = <Duration>[];
  String? loadedUri;

  @override
  Stream<void> get completionEvents => _completion.stream;

  void completeCurrent() => _completion.add(null);

  @override
  Future<void> load(String uri) async => loadedUri = uri;

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> seek(Duration position) async => seekCalls.add(position);

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async => _completion.close();
}

void main() {
  const trackA = Track(
    id: 'a',
    title: '晨光',
    source: TrackSource.file,
    uri: 'a.mp3',
  );
  const trackB = Track(
    id: 'b',
    title: '海风',
    source: TrackSource.file,
    uri: 'b.mp3',
  );

  test('single loop restarts the current track on completion', () async {
    final engine = _FakePlaybackEngine();
    final controller = PlaybackController(engine);
    controller.setQueue([trackA, trackB]);
    await controller.playTrack(trackA);
    controller.setMode(PlayMode.singleLoop);

    engine.completeCurrent();
    await Future<void>.delayed(Duration.zero);

    expect(controller.value.currentTrack?.id, 'a');
    expect(engine.seekCalls.single, Duration.zero);
    await controller.dispose();
  });

  test('next advances through the queue', () async {
    final engine = _FakePlaybackEngine();
    final controller = PlaybackController(engine);
    controller.setQueue([trackA, trackB]);
    await controller.playTrack(trackA);

    await controller.next();

    expect(controller.value.currentTrack?.id, 'b');
    expect(engine.loadedUri, 'b.mp3');
    await controller.dispose();
  });

  test('system media next delegates to the playback queue', () async {
    final engine = _FakePlaybackEngine();
    final controller = PlaybackController(engine);
    controller.setQueue([trackA, trackB]);
    await controller.playTrack(trackA);
    final handler = LocalAudioHandler(controller);

    await handler.skipToNext();

    expect(controller.value.currentTrack?.id, 'b');
    await handler.close();
    await controller.dispose();
  });
}
