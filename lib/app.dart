import 'package:flutter/material.dart';

import 'features/shell/music_home.dart';

class LocalMusicApp extends StatelessWidget {
  const LocalMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFFE5484D);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '本地音乐',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
          surface: const Color(0xFF111114),
        ),
        scaffoldBackgroundColor: const Color(0xFF0B0B0D),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1A1A1F),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: Color(0xFF101014),
          indicatorColor: Color(0x44E5484D),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFF101014),
          indicatorColor: Color(0x44E5484D),
        ),
        useMaterial3: true,
      ),
      home: const MusicHome(),
    );
  }
}
