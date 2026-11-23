# 法语本地化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增原生法语支持，并更新草稿版本的法语元数据及所有语言的更新记录。

**Architecture:** 复用 `.lproj` 与现有 AppLanguage，动态系统文案在来源处本地化；商店元数据使用可审阅 JSON 与限定草稿版本的同步脚本。

**Tech Stack:** SwiftUI、Foundation、XCTest、Python/Node、App Store Connect API。

**Spec:** `docs/superpowers/specs/2026-10-24-french-localization-design.md`

## Global Constraints

- 仅可编辑 0.2.1，不提交审核、不改变已发布版本、歌曲和图片。
- 不改营销版本和构建45；新代码需新构建才可在 TestFlight 生效。
- French fr-FR/fr-CA/fr_CH 正确识别，未知语言回退英语。

## Review Focus

- 法语长标签与窄屏裁切：UI 真实法语启动测试及截图。
- 动态 String 不走 SwiftUI 翻译：覆盖状态、无障碍、菜单和错误边界。
- 百分号占位符类型改变：字符串表格式对齐检查。
- 已发布 AppInfo 被误改：同步前状态／版本限定和备份。
- 商店先写法语但二进制未更新：完成报告明确构建边界。

### Task 1: App 法语资源与动态文案

**Files:** `AppLanguage.swift`、`Resources/fr.lproj/`、相关 Features、`LocalizationPolicyTests.swift`、`LocalizationUITests.swift`、`ios-app/scripts/tests/test_french_localization.py`。

**Interfaces:** 消费现有中文 key；输出 Bundle 的 fr 翻译及 AppLanguage.french，不改播放服务。

- [x] 新增地区映射、关键资源、占位符及法语界面测试，先观察缺资源失败。
- [x] 完成 fr Localizable/InfoPlist，接通实际界面动态文案。
- [ ] 本地脚本回归与原生 XCTest/UI 全量验证；Windows 不冒充原生结果。
- [x] 提交并记录实际验证边界；GitHub 原生验证40110788026尚在执行。

### Task 2: 商店元数据及四语言更新记录

**Files:** `marketing/app-store-2026-10-24/localizations/`、同步工具、项目进度。

**Interfaces:** 消费可编辑版本快照及本轮真实功能，输出 fr-FR 字段和各语言 whatsNew；不使用截图上传接口。

- [x] 回读现有本地化、AppInfo 与0.2描述并备份，核对字段限制。
- [x] 编写 French 元数据和四语言更新记录，校验长度和不可变网址。
- [x] 仅创建缺失 fr-FR，PATCH 明确字段；回读逐字段比较，验证历史版本未改变。
- [x] 独立整轮复核，修复重要问题并记录结果；不标记未运行的原生测试完成。
