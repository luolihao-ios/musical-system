import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_music_player/core/models/playlist.dart';
import 'package:local_music_player/features/playlists/playlists_page.dart';

void main() {
  testWidgets('does not offer delete for the built-in liked playlist', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PlaylistsPage(playlists: [Playlist.liked])),
    );

    expect(find.text('我喜欢'), findsOneWidget);
    expect(find.byTooltip('删除歌单'), findsNothing);
  });
}
