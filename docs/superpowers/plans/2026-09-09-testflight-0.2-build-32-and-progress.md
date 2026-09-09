# 音乐播放器 0.2（32）发布与进度归档实施计划

> **供智能开发执行者使用：** 必须使用 `superpowers:executing-plans` 按任务逐项执行并验证。

**目标：** 以 `codex/aiyue-greenfield` 为唯一基线，合入导入歌曲时程序化生成封面的功能，补齐当前项目进度文档，并上传音乐播放器 `0.2 (32)` 到 TestFlight。

**架构：** 保留最新分支现有的统一播放、传输共享容器和诊断能力，只迁移程序化封面提交中与音乐导入有关的文件。发布版本由 `ios-app/project.yml` 明确记录，GitHub Actions 使用该构建号归档，避免工作流运行序号与 App 构建号混淆。

**技术栈：** Swift 6、SwiftUI、AVFoundation、XcodeGen、Python unittest、GitHub Actions、App Store Connect API。

**规格：** `docs/superpowers/specs/2026-09-09-procedural-import-artwork-design.md`

## 全局约束

- 唯一开发基线：`codex/aiyue-greenfield`。
- 音乐播放器发布版本：`0.2 (32)`。
- 不引入 AI、联网封面搜索或歌词生成。
- 不提交诊断产物、IPA、证书、描述文件和营销临时文件。
- 项目进度文档使用中文。

---

### 任务一：迁移程序化封面功能

**文件：**
- 修改：`ios-app/LocalMusicPlayer/Import/FileImportService.swift`
- 新增：`ios-app/LocalMusicPlayer/Import/ProceduralArtworkGenerator.swift`
- 修改：`ios-app/LocalMusicPlayer/Import/SystemLibraryImporter.swift`
- 测试：`ios-app/LocalMusicPlayerTests/*Import*Tests.swift`

- [x] 将提交 `b8e84da` 迁移到当前分支并解决与最新导入流程的冲突。
- [x] 确认有内嵌封面时保留原封面，无封面时稳定生成 JPEG 封面。
- [x] 运行相关测试并确认现有导入行为未回退。

### 任务二：固定发布元数据

**文件：**
- 修改：`ios-app/project.yml`
- 修改：`.github/workflows/ios-app-store.yml`
- 修改：`ios-app/scripts/tests/test_release_metadata.py`

- [x] 将工程版本设置为 `0.2 (32)`。
- [x] 让发布工作流使用工程中的构建号，而不是 GitHub 工作流运行序号。
- [x] 运行发布元数据测试，确认 Bundle ID、签名配置和 App Group 检查保持不变。

### 任务三：补齐持续开发进度文档

**文件：**
- 新增：`docs/项目进度.md`

- [x] 记录当前分支、版本、最近 TestFlight 基线、已完成功能和已知待办。
- [x] 明确区分音乐播放器与爱乐互传的构建号。
- [x] 记录下一次开发和发布前必须更新的字段。

### 任务四：验证、推送并上传 TestFlight

**文件：**
- 验证：`ios-app/scripts/verify.sh` 及发布元数据测试

- [x] 检查暂存内容，确保没有证书和诊断产物。
- [x] 运行当前环境可执行的完整本地检查。
- [ ] 提交并推送 `codex/aiyue-greenfield`。
- [ ] 手动触发 `ios-app-store.yml`，确认其以 `0.2 (32)` 完成验证和上传；若仅处于 GitHub 构建等待阶段，则按项目规则停止轮询。
