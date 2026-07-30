# 暮色音乐

一款只整理和播放设备本地音频的音乐播放器，不接入在线曲库，也不下载或上传音乐。Windows 与 iOS 使用独立的原生工程和本地数据库。

## Windows 原生版

- C# 14、.NET 10、WPF，支持 Windows 10/11 x64。
- 递归扫描用户选择的文件夹，读取歌曲、歌手、专辑、封面和同名 `.lrc`。
- 支持 MP3、M4A/AAC、FLAC、WAV、OGG Vorbis。
- 支持搜索、我喜欢、自建歌单、播放队列、单曲循环、列表循环和随机播放。
- 支持系统媒体键、Windows 媒体面板，以及带歌词高亮的沉浸式唱片页面。
- 自包含发布，用户电脑不需要预装 .NET、Visual Studio 或 Windows SDK。
- 安装包按当前用户安装，无需管理员权限，并允许选择安装目录。

### 本地验证

```powershell
.\windows-app\scripts\verify.ps1
```

### 生成便携程序和安装包

安装 Inno Setup 7 后运行：

```powershell
.\windows-app\scripts\package.ps1 -IsccPath "E:\DevTools\Inno Setup 7\ISCC.exe"
```

输出：

- `windows-app/artifacts/publish/LocalMusicPlayer.exe`
- `windows-app/artifacts/installer/LocalMusicPlayer-Setup.exe`

播放器数据库、扫描目录、喜欢和歌单保存在：

```text
%LOCALAPPDATA%\luolihao\LocalMusicPlayer
```

卸载应用默认不会删除这里的个人资料库数据。

### Windows 本机验证记录

- 验证日期：2026-07-30
- 系统：Windows 10 `10.0.19045.0` x64
- .NET SDK：`10.0.301`
- Inno Setup：`7.0.2` x64，当前用户安装于 `E:\DevTools\Inno Setup 7`
- Release 构建：0 警告、0 错误
- 自动测试：34 项全部通过
- NuGet 漏洞检查：应用与测试项目均未发现已知漏洞
- 安装生命周期：当前用户静默安装、启动、覆盖安装、卸载均通过；卸载后本地资料库数据库仍保留
- 当前安装包：58,372,405 字节
- 当前安装包 SHA-256：`6E960D293D7F343ED42A7CD65FBA6C987A9D3D442720726127A46386D3DC64F7`

## iOS 原生版

- Swift 6、SwiftUI、SwiftData，最低 iOS 17。
- 支持从“文件”导入 MP3、M4A/AAC、FLAC、WAV、AIFF 和同名 LRC。
- 支持授权读取设备音乐资料库中具有本地 `assetURL` 的可播放歌曲；云端或受保护且没有本地 URL 的项目不会被导入。
- 支持搜索、喜欢、自建歌单、后台播放、锁屏控制、同步歌词和无歌词唱片动画。
- iOS 与 Windows 使用完全独立的数据库，不同步数据。

### GitHub 生成爱思测试包

手动运行 `iOS native unsigned IPA` 工作流，下载：

```text
LocalMusicPlayer-iOS-unsigned/LocalMusicPlayer-unsigned.ipa
```

该流程不读取证书、私钥或描述文件。下载后使用爱思助手签名并安装到 iOS 17+ 真机。

### App Store Connect

`iOS App Store Connect upload` 工作流只允许手动触发。它引用仓库 Secrets 中的 Apple Distribution 证书、App Store 描述文件和 App Store Connect API Key，在临时钥匙串中签名、归档并上传，完成后始终清理临时签名材料。
