# 爱乐互传 LocalSend 风格传输重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将爱乐互传 Windows/iOS 改为自动发现、确认式局域网互传，并增加包含音频、歌词和封面的 `.aiyuepack` 音乐包。

**Architecture:** 保留现有 Windows WPF 与 iOS SwiftUI 客户端，替换发现层和 HTTP 传输层为 LocalSend v2 风格的设备信息、注册、准备上传、上传、取消接口。音乐包作为普通文件传输之上的独立打包层，接收后经用户确认再解包和导入音乐播放器。

**Tech Stack:** .NET 10/WPF, Swift 6/SwiftUI, Network.framework, Makaretu.Dns.Multicast, ZIP, SHA-256, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-02-aiyue-localsend-transfer-design.md`

## Global Constraints

- 首要互通目标是爱乐互传自己的 Windows 与 iOS；官方 LocalSend 兼容为可选项。
- 每次传输必须由接收端明确接受或拒绝。
- 支持任意文件、文件夹、文本和剪贴板。
- `.aiyuepack` 必须包含 manifest、音频、歌词和封面，并校验后再导入。
- 不依赖公网服务器；发现失败时提供网络诊断提示。

---

### Task 1: 统一 LocalSend 风格协议模型

**Files:**
- Modify: `transfer-windows/src/MuseTransfer.Protocol/*`
- Modify: `transfer-ios/MuseTransfer/Protocol/*`
- Create: `transfer-windows/tests/MuseTransfer.Tests/Protocol/LocalSendProtocolTests.cs`
- Create: `transfer-ios/MuseTransferTests/LocalSendProtocolTests.swift`

- [ ] 定义 `DeviceInfo`、`FileMetadata`、`PrepareUploadRequest/Response` 与 `/register` 数据模型。
- [ ] 为 JSON 编码添加协议版本、设备类型、指纹、端口和传输能力字段。
- [ ] 用固定 JSON 向量测试 Windows 与 iOS 编解码结果一致。
- [ ] 保留当前加密和 SHA-256 能力作为实现扩展，不让协议模型依赖 UI。
- [ ] 运行 Windows 及 iOS 协议测试并提交。

### Task 2: 自动发现与刷新

**Files:**
- Modify: `transfer-windows/src/MuseTransfer.App/Discovery/MdnsAdvertiser.cs`
- Create: `transfer-windows/src/MuseTransfer.App/Discovery/LocalSendDiscovery.cs`
- Modify: `transfer-ios/MuseTransfer/Discovery/ServiceAdvertiser.swift`
- Modify: `transfer-ios/MuseTransfer/Discovery/NearbyDeviceBrowser.swift`
- Modify: `transfer-windows/tests/MuseTransfer.Tests/Discovery/*`

- [ ] Windows 广播改为 LocalSend 风格设备信息，使用 UDP 224.0.0.167:53317。
- [ ] 增加 HTTP `/api/localsend/v2/register` 回退发现，并去重自身设备。
- [ ] iOS 使用 Bonjour 同一服务类型，统一设备信息和能力字段。
- [ ] 增加“刷新”操作，清理过期设备并重新发起发现。
- [ ] 测试广播解析、HTTP 回退和刷新后的列表状态。

### Task 3: 重做发送/接收接口

**Files:**
- Modify: `transfer-windows/src/MuseTransfer.App/Networking/ReceiverHost.cs`
- Modify: `transfer-windows/src/MuseTransfer.App/Networking/TransferClient.cs`
- Modify: `transfer-ios/MuseTransfer/Transfer/ReceiverServer.swift`
- Modify: `transfer-ios/MuseTransfer/Transfer/TransferClient.swift`
- Modify: `transfer-windows/tests/MuseTransfer.Tests/Networking/*`
- Modify: `transfer-ios/MuseTransferTests/TransferSessionTests.swift`

- [ ] 实现 `/prepare-upload` 元数据请求和接收端待确认会话。
- [ ] 实现 `/upload` 二进制传输、并发文件、取消和 SHA-256 校验。
- [ ] 保留安全相对路径、临时文件和原子移动。
- [ ] 使 Windows 与 iOS 的接受、拒绝、超时和取消状态一致。
- [ ] 用跨平台测试覆盖单文件、多文件和大文件分片。

### Task 4: 重做主界面和设置

**Files:**
- Modify: `transfer-windows/src/MuseTransfer.App/MainWindow.xaml`
- Modify: `transfer-windows/src/MuseTransfer.App/MainWindow.xaml.cs`
- Modify: `transfer-windows/src/MuseTransfer.App/ViewModels/TransferViewModel.cs`
- Modify: `transfer-ios/MuseTransfer/Features/Transfer/*`
- Modify: `transfer-ios/MuseTransfer/Features/Settings/*`

- [ ] 移除手动地址、公钥输入框，加入文件、文件夹、文本、剪贴板和刷新按钮。
- [ ] 用设备卡片显示名称、类型、在线状态和传输入口。
- [ ] 增加接收确认弹窗、进度、取消和错误提示。
- [ ] 设置页只保留设备名、接收目录、开机启动、发现开关和版本信息。
- [ ] 测试无设备、刷新、选中文件、拒绝和取消等状态。

### Task 5: 音乐包与播放器导入

**Files:**
- Create: `transfer-windows/src/MuseTransfer.Core/Music/AiyuePack.cs`
- Create: `transfer-windows/src/MuseTransfer.Core/Music/AiyuePackManifest.cs`
- Create: `transfer-ios/MuseTransfer/Music/AiyuePack.swift`
- Modify: `windows-app/src/LocalMusicPlayer/Import/TransferHandoffImporter.cs`
- Modify: `ios-app/LocalMusicPlayer/Import/TransferHandoffImporter.swift`
- Create: `transfer-windows/tests/MuseTransfer.Tests/Music/AiyuePackTests.cs`
- Create: `transfer-ios/MuseTransferTests/AiyuePackTests.swift`

- [ ] 定义 `.aiyuepack` ZIP 结构和 manifest 字段。
- [ ] 根据音频、同名歌词和封面生成歌曲包，并记录每个文件的 SHA-256。
- [ ] 接收端先校验 ZIP 和 manifest，再显示歌曲信息供用户确认。
- [ ] 解包到安全临时目录，校验通过后调用现有音乐导入接口。
- [ ] 覆盖缺歌词、缺封面、重复歌曲、损坏包和路径穿越测试。

### Task 6: 打包、权限与发布验证

**Files:**
- Modify: `transfer-windows/installer/MuseTransfer.iss`
- Modify: `.github/workflows/windows-build.yml`
- Modify: `.github/workflows/ios-artifact.yml`
- Modify: `transfer-windows/scripts/verify.ps1`
- Modify: `transfer-ios/scripts/verify.sh`

- [ ] 加入 Windows 防火墙和专用网络提示，验证默认 Program Files 目录和自定义目录。
- [ ] 确认 Windows 程序图标、桌面快捷方式和卸载入口使用统一图标。
- [ ] GitHub Actions 在同一 workflow 生成 Windows 安装包和 iOS IPA。
- [ ] 发布前运行协议、发现、传输、音乐包和安装测试。
- [ ] 在真实 Windows+iPhone 同一 Wi‑Fi 环境完成端到端验收。

