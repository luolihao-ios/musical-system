import 'package:flutter_test/flutter_test.dart';
import 'package:local_music_player/core/services/lrc_parser.dart';

void main() {
  test('parses multiple timestamps in chronological order', () {
    final lines = LrcParser().parse('[00:03.40][00:01.20]晨光\n[00:05.000]醒来');

    expect(lines.map((line) => line.at), [
      const Duration(milliseconds: 1200),
      const Duration(milliseconds: 3400),
      const Duration(seconds: 5),
    ]);
    expect(lines.first.text, '晨光');
  });

  test('returns no lines for invalid lyrics', () {
    expect(LrcParser().parse('纯文本，没有时间轴'), isEmpty);
  });
}
