import '../models/lyric_line.dart';

class LrcParser {
  static final _timestamp = RegExp(r'\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]');

  List<LyricLine> parse(String text) {
    final result = <LyricLine>[];
    for (final rawLine in text.split(RegExp(r'\r?\n'))) {
      final matches = _timestamp.allMatches(rawLine).toList(growable: false);
      if (matches.isEmpty) continue;
      final content = rawLine.replaceAll(_timestamp, '').trim();
      if (content.isEmpty) continue;
      for (final match in matches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final fraction = match.group(3);
        final milliseconds = switch (fraction?.length) {
          1 => int.parse(fraction!) * 100,
          2 => int.parse(fraction!) * 10,
          3 => int.parse(fraction!),
          _ => 0,
        };
        result.add(
          LyricLine(
            at: Duration(
              minutes: minutes,
              seconds: seconds,
              milliseconds: milliseconds,
            ),
            text: content,
          ),
        );
      }
    }
    result.sort((left, right) => left.at.compareTo(right.at));
    return List.unmodifiable(result);
  }
}
