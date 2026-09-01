# 暮色音乐交接协议 v1

传输工具不会直接修改播放器资料库。用户在传输完成后明确选择“导入暮色音乐”，工具才将所选音乐及歌词复制到受限交接目录，并原子写入 `music-handoff-v1.json`。

```json
{
  "version": 1,
  "handoffId": "uuid",
  "createdAt": "ISO-8601",
  "items": [
    { "relativePath": "Album/song.mp3", "sha256": "lowercase hex", "kind": "audio" },
    { "relativePath": "Album/song.lrc", "sha256": "lowercase hex", "kind": "lyrics" }
  ]
}
```

- iOS 使用 App Group `group.com.luolihao.aiyuetransfer` 下的 `MusicHandoff/<handoffId>`。
- Windows 使用当前用户本地应用数据下的 `AiYueTransfer/MusicHandoff/<handoffId>`。
- 播放器必须拒绝绝对路径、`..`、符号链接逃逸和摘要不符的项目。
- 播放器以 `handoffId` 记录幂等处理状态，成功或终止失败后清理一次性交接目录。
- URI 为 `musemusic://import?handoff=<handoffId>`；Windows 还允许同用户范围的 `manifest=<escaped absolute path>`。
- 不支持的普通文件仍保留在接收目录，不进入播放器资料库。
