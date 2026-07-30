import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_music_player/features/shell/adaptive_shell.dart';

Widget _app() {
  return MaterialApp(
    home: AdaptiveShell(
      selectedIndex: 0,
      onDestinationSelected: (_) {},
      destinations: const [
        AdaptiveDestination(
          icon: Icons.library_music_outlined,
          selectedIcon: Icons.library_music,
          label: '音乐库',
        ),
        AdaptiveDestination(
          icon: Icons.queue_music_outlined,
          selectedIcon: Icons.queue_music,
          label: '歌单',
        ),
      ],
      body: const SizedBox.expand(),
    ),
  );
}

void main() {
  testWidgets('uses rail on desktop and bottom navigation on phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpWidget(_app());
    expect(find.byType(NavigationRail), findsOneWidget);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(_app());
    await tester.pump();
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
