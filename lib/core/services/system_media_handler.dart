import 'package:audio_service/audio_service.dart';

import 'playback_controller.dart';

class LocalAudioHandler extends BaseAudioHandler {
  LocalAudioHandler(this._controller) {
    _controller.state.addListener(_publishState);
    _publishState();
  }

  final PlaybackController _controller;

  void _publishState() {
    final snapshot = _controller.value;
    final track = snapshot.currentTrack;
    mediaItem.add(
      track == null
          ? null
          : MediaItem(
              id: track.id,
              title: track.title,
              artist: track.artist,
              album: track.album,
              duration: track.duration,
            ),
    );
    playbackState.add(
      PlaybackState(
        controls: const [
          MediaControl.skipToPrevious,
          MediaControl.play,
          MediaControl.pause,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        processingState: AudioProcessingState.ready,
        playing: snapshot.isPlaying,
        updatePosition: snapshot.position,
        queueIndex: snapshot.currentIndex < 0 ? null : snapshot.currentIndex,
      ),
    );
  }

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> seek(Duration position) => _controller.seek(position);

  @override
  Future<void> skipToNext() => _controller.next();

  @override
  Future<void> skipToPrevious() => _controller.previous();

  Future<void> close() async {
    _controller.state.removeListener(_publishState);
  }
}
