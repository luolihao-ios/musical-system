import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_music_player/core/models/track.dart';
import 'package:local_music_player/features/library/library_page.dart';

void main() {
  testWidgets('filters local tracks by title and artist', (tester) async {
    const tracks = [
      Track(id: '1', title: '海风', artist: '陈晓', source: TrackSource.file),
      Track(id: '2', title: '晨光', artist: '林雨', source: TrackSource.file),
    ];
    await tester.pumpWidget(
      const MaterialApp(home: LibraryPage(tracks: tracks)),
    );

    await tester.enterText(find.byType(TextField), '陈晓');
    await tester.pump();

    expect(find.text('海风'), findsOneWidget);
    expect(find.text('晨光'), findsNothing);
  });
}
