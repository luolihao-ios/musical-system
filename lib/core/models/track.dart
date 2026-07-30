enum TrackSource { file, iosMediaLibrary }

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.source,
    this.artist = '未知歌手',
    this.album,
    this.uri,
    this.duration = Duration.zero,
    this.artworkPath,
    this.lyricPath,
    this.isLiked = false,
    this.importedAt,
    this.lastPlayedAt,
  });

  final String id;
  final String title;
  final TrackSource source;
  final String artist;
  final String? album;
  final String? uri;
  final Duration duration;
  final String? artworkPath;
  final String? lyricPath;
  final bool isLiked;
  final DateTime? importedAt;
  final DateTime? lastPlayedAt;
}
