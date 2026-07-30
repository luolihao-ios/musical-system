import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/track.dart';

typedef DestinationDirectoryProvider = Future<Directory> Function();

class FileImporter {
  FileImporter({DestinationDirectoryProvider? destinationDirectory})
    : _destinationDirectory =
          destinationDirectory ?? _defaultDestinationDirectory;

  final DestinationDirectoryProvider _destinationDirectory;

  bool get isAvailable => true;

  Future<Track> importPath(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('选择的音频文件不存在', sourcePath);
    }
    final destination = await _destinationDirectory();
    await destination.create(recursive: true);
    final filename = _filename(sourcePath);
    final target = File(
      '${destination.path}${Platform.pathSeparator}'
      '${DateTime.now().microsecondsSinceEpoch}-$filename',
    );
    await source.copy(target.path);
    return Track(
      id: 'file:${target.absolute.path.replaceAll('\\', '/').toLowerCase()}',
      title: _stem(filename),
      source: TrackSource.file,
      uri: target.path,
      importedAt: DateTime.now(),
    );
  }

  static Future<Directory> _defaultDestinationDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory('${documents.path}${Platform.pathSeparator}music');
  }

  String _filename(String path) {
    return path.substring(path.lastIndexOf(Platform.pathSeparator) + 1);
  }

  String _stem(String filename) {
    final dot = filename.lastIndexOf('.');
    return dot > 0 ? filename.substring(0, dot) : filename;
  }
}
