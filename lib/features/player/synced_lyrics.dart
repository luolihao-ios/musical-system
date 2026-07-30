import 'package:flutter/material.dart';

import '../../core/models/lyric_line.dart';

class SyncedLyrics extends StatelessWidget {
  const SyncedLyrics({super.key, required this.position, required this.lines});

  final Duration position;
  final List<LyricLine> lines;

  @override
  Widget build(BuildContext context) {
    var activeIndex = -1;
    for (var index = 0; index < lines.length; index++) {
      if (lines[index].at <= position) activeIndex = index;
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 80),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final active = index == activeIndex;
        return AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 220),
          style: Theme.of(context).textTheme.titleMedium!.copyWith(
            color: active ? Colors.white : Colors.white38,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
            child: Text(lines[index].text, textAlign: TextAlign.center),
          ),
        );
      },
    );
  }
}
