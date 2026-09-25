# 爱乐之城音乐播放器

一款以设备本地音乐为核心，同时提供开放许可音乐下载、缺失歌词与封面补全的原生音乐播放器。用户导入的音频、资料库、收藏、歌单和播放状态保存在设备本地；在线能力只处理用户主动搜索的开放许可音乐，或为缺失资料的歌曲查询歌词与封面，不会上传用户的音频文件。

当前持续开发基线、发布版本和待办事项见 [`docs/项目进度.md`](docs/项目进度.md)。

## 暮色互传

仓库同时包含独立的 Windows 与 iOS 局域网传输工具，支持任意文件和文件夹，并对音乐、同名歌词、封面及播放列表进行识别。两端仅使用自有 Muse Transfer v2 协议互通：Bonjour/mDNS 发现、P-256 密钥协商、HKDF-SHA256、AES-256-GCM、1 MiB 分块和 SHA-256 最终校验。每批接收都必须由用户明确接受，拒绝前不会上传文件正文。

- Windows 工程：`transfer-windows/MuseTransfer.slnx`
- iOS 工程定义：`transfer-ios/project.yml`
- 协议：`docs/transfer-protocol/v2.md`
- 真机验收：`docs/transfer-protocol/acceptance-checklist.md`

音乐传输完成后，用户可以显式选择“导入暮色音乐”。交接清单会再次校验路径和文件摘要，并通过 `handoffId` 防止重复导入；普通文件不会进入播放器资料库。

Windows 安装包和 iOS 模拟器构建分别由 `Muse Transfer Windows`、`Muse Transfer iOS` GitHub Actions 工作流生成。目前工作流保留为手动触发，以便功能完整后集中验证。

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
- 支持从“文件”、授权文件夹、设备音乐资料库、爱乐互传包导入 MP3、M4A/AAC、FLAC、WAV、AIFF 和同名 LRC。
- 支持授权读取设备音乐资料库中具有本地 `assetURL` 的可播放歌曲；云端或受保护且没有本地 URL 的项目不会被导入。
- 导入时优先保留内嵌或随文件提供的资料；缺少封面时生成程序化 JPEG 封面，缺少歌词或封面时会按歌曲标题、歌手、专辑和时长查询在线资料并仅保存匹配结果。
- 提供在线音乐搜索、试听和下载入口；仅允许下载已标明公共领域或 Creative Commons 许可的曲目，下载后作为本地文件加入资料库。
- 支持歌曲搜索、专辑/歌手/文件夹浏览、最近播放、收藏和自建歌单。
- 自建歌单支持创建、改名、删除、添加/移除歌曲和拖动排序。
- 支持播放队列点选、上一首/下一首、进度、音量、列表循环、单曲循环和随机播放。
- 支持后台播放、锁屏/耳机控制、同步歌词、封面/歌词切换、动态声波和无歌词唱片光影动画。
- 迷你播放器与详情页为同一个底部面板：上滑展开，下滑超过起始高度三分之一后松手关闭，较短下滑回弹；设置页可导出导入、播放和播放器交互诊断日志。
- iOS 与 Windows 使用完全独立的数据库，不同步数据。

当前持续开发分支的 iOS 自动验证包括 85 项单元测试和 5 项播放器交互界面测试，覆盖导入、资料库、歌单、播放状态、系统媒体控制、歌词、封面/歌词切换、队列和底部播放器手势。Xcode 编译与 XCTest 由 GitHub 的 macOS runner 执行；Windows 本机仅做源码、资源、Plist 和工作流静态检查。

### GitHub 生成爱思测试包

手动运行 `iOS native unsigned IPA` 工作流，下载：

```text
LocalMusicPlayer-iOS-unsigned/LocalMusicPlayer-unsigned.ipa
```

该流程不读取证书、私钥或描述文件。下载后使用爱思助手签名并安装到 iOS 17+ 真机。

### App Store Connect

`iOS App Store Connect upload` 工作流只允许手动触发。它引用仓库 Secrets 中的 Apple Distribution 证书、App Store 描述文件和 App Store Connect API Key，在临时钥匙串中签名、归档并上传，完成后始终清理临时签名材料。
