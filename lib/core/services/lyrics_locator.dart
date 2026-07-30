import 'dart:io';

class LyricsLocator {
  const LyricsLocator();

  Future<File?> findForAudio(File audio) async {
    final separator = Platform.pathSeparator;
    final lastSeparator = audio.path.lastIndexOf(separator);
    final lastDot = audio.path.lastIndexOf('.');
    final hasExtension = lastDot > lastSeparator;
    final stem = hasExtension ? audio.path.substring(0, lastDot) : audio.path;
    final lyrics = File('$stem.lrc');
    return await lyrics.exists() ? lyrics : null;
  }
}
