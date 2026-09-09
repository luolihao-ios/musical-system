# 导入歌曲程序化封面实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为缺少内嵌封面的导入歌曲自动生成并保存轻量原创封面。

**Architecture:** 新增独立的 `ImportedArtworkGenerating` 接口与 UIKit 实现，导入服务在元数据解析完成后选择内嵌封面或生成封面。生成失败采用无封面回退，确保批量导入不中断。

**Tech Stack:** Swift 6、UIKit、CryptoKit、XCTest、XcodeGen

**Spec:** `docs/superpowers/specs/2026-09-09-procedural-import-artwork-design.md`

## Global Constraints

- 最低支持 iOS 17。
- 不增加网络请求、AI 模型或第三方运行时依赖。
- 已有封面绝不覆盖，歌词逻辑不修改。
- 项目文档使用中文。

---

### Task 1: 程序化封面生成器

**Files:**
- Create: `ios-app/LocalMusicPlayer/Import/ProceduralArtworkGenerator.swift`
- Create: `ios-app/LocalMusicPlayerTests/ProceduralArtworkGeneratorTests.swift`

**Interfaces:**
- Produces: `ImportedArtworkGenerating.generateArtwork(title:artist:seed:) throws -> Data`

- [ ] **Step 1: 写输出尺寸、不透明性、稳定性和差异性的失败测试**
- [ ] **Step 2: 运行生成器测试，确认因类型不存在而失败**
- [ ] **Step 3: 用 UIKit 固定画布、SHA-256 配色及 JPEG 编码实现最小生成器**
- [ ] **Step 4: 运行生成器测试并确认通过**

### Task 2: 接入导入流程

**Files:**
- Modify: `ios-app/LocalMusicPlayer/Import/FileImportService.swift`
- Modify: `ios-app/LocalMusicPlayerTests/FileImportServiceTests.swift`

**Interfaces:**
- Consumes: `ImportedArtworkGenerating.generateArtwork(title:artist:seed:) throws -> Data`
- Produces: 缺图歌曲的 `TrackRecord.artworkReference`

- [ ] **Step 1: 写缺图生成、内嵌优先和失败回退的导入测试**
- [ ] **Step 2: 运行导入测试，确认缺图行为测试失败**
- [ ] **Step 3: 注入生成器并在元数据回退完成后选择封面来源**
- [ ] **Step 4: 运行导入测试并确认通过**

### Task 3: 全量验证

**Files:**
- Modify: `ios-app/LocalMusicPlayer/Import/SystemLibraryImporter.swift`
- Modify: `ios-app/LocalMusicPlayerTests/SystemLibraryImporterTests.swift`

**Interfaces:**
- Consumes: `ImportedArtworkGenerating.generateArtwork(title:artist:seed:) throws -> Data`
- Produces: 缺图系统歌曲的 `TrackRecord.artworkReference`

- [ ] **Step 1: 写系统歌曲缺图生成封面的失败测试**
- [ ] **Step 2: 运行测试，确认因构造参数不存在而失败**
- [ ] **Step 3: 将共享生成器注入系统资料库导入器，并保留系统已有封面**
- [ ] **Step 4: 运行系统资料库导入测试并确认通过**

### Task 4: 全量验证

**Files:**
- Modify: `docs/superpowers/plans/2026-09-09-procedural-import-artwork.md`

- [ ] **Step 1: 运行 Windows 可执行的脚本测试与静态检查**
- [ ] **Step 2: 检查差异，确认未改动歌词及已有封面优先级**
- [ ] **Step 3: 提交分支并推送，等待 GitHub macOS 测试构建**
