import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/models/lyric_line.dart';
import '../../core/models/playlist.dart';
import '../../core/models/track.dart';
import '../../core/services/audio_metadata_reader.dart';
import '../../core/services/file_importer.dart';
import '../../core/services/lrc_parser.dart';
import '../../core/services/lyrics_locator.dart';
import '../../core/services/music_scanner.dart';
import '../../core/services/music_source_gateway.dart';
import '../../core/services/playback_controller.dart';
import '../library/library_page.dart';
import '../library/scan_import_sheet.dart';
import '../player/mini_player.dart';
import '../player/now_playing_page.dart';
import '../playlists/playlists_page.dart';
import 'adaptive_shell.dart';

class MusicHome extends StatefulWidget {
  const MusicHome({super.key});

  @override
  State<MusicHome> createState() => _MusicHomeState();
}

class _MusicHomeState extends State<MusicHome> {
  final _importer = FileImporter();
  final _iosGateway = const IosMusicSourceGateway();
  var _tracks = <Track>[];
  var _selectedIndex = 0;
  PlaybackController? _playback;

  PlaybackController get _player =>
      _playback ??= PlaybackController(JustAudioPlaybackEngine());

  @override
  void dispose() {
    _playback?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      LibraryPage(
        tracks: _tracks,
        onImport: _showImportSheet,
        onPlay: _play,
        onToggleLike: _toggleLike,
      ),
      const PlaylistsPage(playlists: [Playlist.liked]),
    ];
    return AdaptiveShell(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) => setState(() => _selectedIndex = index),
      destinations: const [
        AdaptiveDestination(
          icon: Icons.library_music_outlined,
          selectedIcon: Icons.library_music_rounded,
          label: '音乐库',
        ),
        AdaptiveDestination(
          icon: Icons.queue_music_outlined,
          selectedIcon: Icons.queue_music_rounded,
          label: '歌单',
        ),
      ],
      body: IndexedStack(index: _selectedIndex, children: pages),
      miniPlayer: _playback == null
          ? null
          : ValueListenableBuilder(
              valueListenable: _player.state,
              builder: (context, snapshot, _) => MiniPlayer(
                snapshot: snapshot,
                onOpen: _openNowPlaying,
                onPlayPause: snapshot.isPlaying ? _player.pause : _player.play,
                onNext: _player.next,
              ),
            ),
    );
  }

  Future<void> _showImportSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ScanImportSheet(
        isWindows: Platform.isWindows,
        onChooseFolder: () {
          Navigator.pop(context);
          _scanFolder();
        },
        onChooseFiles: () {
          Navigator.pop(context);
          _importFiles();
        },
        onReadMediaLibrary: () {
          Navigator.pop(context);
          _readIosLibrary();
        },
      ),
    );
  }

  Future<void> _scanFolder() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null || !mounted) return;
    try {
      final result = await MusicScanner(
        metadataReader: MetadataGodAudioMetadataReader(),
        lyricsLocator: const LyricsLocator(),
      ).scanDirectory(Directory(path));
      if (!mounted) return;
      setState(() => _tracks = result.tracks);
      _message('已收集 ${result.indexedCount} 首本地歌曲');
    } on Object catch (error) {
      _message('扫描失败：$error');
    }
  }

  Future<void> _importFiles() async {
    final selection = await FilePicker.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );
    if (selection == null) return;
    final imported = <Track>[];
    for (final file in selection.files) {
      if (file.path != null) {
        imported.add(await _importer.importPath(file.path!));
      }
    }
    if (!mounted) return;
    setState(() => _tracks = [..._tracks, ...imported]);
    _message('已导入 ${imported.length} 首歌曲');
  }

  Future<void> _readIosLibrary() async {
    final access = await _iosGateway.requestMediaLibraryAccess();
    if (access != MediaLibraryAccess.authorized) {
      _message('未获得音乐资料库权限，仍可从“文件”导入');
      return;
    }
    final tracks = await _iosGateway.listDeviceTracks();
    if (!mounted) return;
    setState(() => _tracks = tracks);
    _message('已读取 ${tracks.length} 首设备歌曲');
  }

  Future<void> _play(Track track) async {
    try {
      _player.setQueue(_tracks);
      await _player.playTrack(track);
      if (mounted) setState(() {});
    } on Object catch (error) {
      _message('无法播放：$error');
    }
  }

  void _toggleLike(Track target) {
    setState(() {
      _tracks = [
        for (final track in _tracks)
          if (track.id == target.id)
            _withLike(track, !track.isLiked)
          else
            track,
      ];
    });
  }

  Track _withLike(Track track, bool liked) {
    return Track(
      id: track.id,
      title: track.title,
      source: track.source,
      artist: track.artist,
      album: track.album,
      uri: track.uri,
      duration: track.duration,
      artworkPath: track.artworkPath,
      lyricPath: track.lyricPath,
      isLiked: liked,
      importedAt: track.importedAt,
      lastPlayedAt: track.lastPlayedAt,
    );
  }

  Future<void> _openNowPlaying() async {
    final track = _player.value.currentTrack;
    if (track == null) return;
    var lyrics = const <LyricLine>[];
    if (track.lyricPath != null) {
      try {
        lyrics = LrcParser().parse(await File(track.lyricPath!).readAsString());
      } on Object {
        lyrics = const [];
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => NowPlayingPage(controller: _player, lyrics: lyrics),
      ),
    );
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
