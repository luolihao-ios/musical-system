import 'package:flutter/material.dart';

class LocalMusicApp extends StatelessWidget {
  const LocalMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '本地音乐',
      home: const Scaffold(body: Center(child: Text('导入本地音乐'))),
    );
  }
}
