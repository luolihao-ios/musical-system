import 'package:flutter_test/flutter_test.dart';
import 'package:local_music_player/main.dart';

void main() {
  testWidgets('renders the local-music empty state', (tester) async {
    await tester.pumpWidget(const LocalMusicApp());

    expect(find.text('导入本地音乐'), findsOneWidget);
  });
}
