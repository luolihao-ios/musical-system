import 'package:flutter/material.dart';

class ScanImportSheet extends StatelessWidget {
  const ScanImportSheet({
    super.key,
    required this.isWindows,
    required this.onChooseFolder,
    required this.onChooseFiles,
    this.onReadMediaLibrary,
  });

  final bool isWindows;
  final VoidCallback onChooseFolder;
  final VoidCallback onChooseFiles;
  final VoidCallback? onReadMediaLibrary;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('添加本地音乐', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (isWindows)
              ListTile(
                leading: const Icon(Icons.folder_open_rounded),
                title: const Text('扫描音乐文件夹'),
                onTap: onChooseFolder,
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.library_music_rounded),
                title: const Text('读取设备音乐资料库'),
                onTap: onReadMediaLibrary,
              ),
              ListTile(
                leading: const Icon(Icons.file_open_rounded),
                title: const Text('从“文件”导入'),
                onTap: onChooseFiles,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
