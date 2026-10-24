# 多设备自适应实施计划

> 执行方式：本会话原生执行，使用 executing-plans；用户已明确免除后续设计确认。实现完成后进行一次独立代码复核。

**目标：** 保持 iPhone 行为，补齐 iPad/Duo 大屏布局，再制作真实截图。
**架构：** 纯尺寸策略负责分栏、封面大小和菜单避让，现有播放模型保持唯一；SwiftUI 按窗口实时重排。
**技术：** Swift 6、SwiftUI、XCTest、GitHub Actions、Xcode 27.1。
**设计：** `docs/superpowers/specs/2026-10-24-adaptive-player-design.md`。

## 全局约束

- iOS 17.0 起；无 Watch target/截图；不改变歌曲数据、导入和联网接口。
- 保留点击小播放器展开、下拉收起、上滑切歌；歌词点击不定位播放。
- 不为仅验证的构建增加构件号，不自动上传新 App。
- 项目文档中文；Windows 检查不代替 Apple 原生构建。

## 复核重点

窄窗口与横屏高度不足；长歌名/大字体；菜单变为侧边栏；播放时旋转或折叠导致模型重建；歌词滚动与整页手势冲突。

### Task 1: 尺寸策略和大屏播放器

**文件：** 新建 `AdaptivePlayerLayout.swift`、对应 XCTest；修改 `NowPlayingView.swift`。
**接口：** `AdaptivePlayerLayout.resolve(size: CGSize) -> AdaptivePlayerLayout`，输出 `isWide`、`artworkSide`、`columnWidth`；宽屏阈值 720 点、最小可用高 420 点，列间距 32 点，水平外边距 32 点。
- [ ] 写边界测试：393×700 单列、1024×1200 分栏且封面>390、700×900 单列、900×350 单列、Duo 内外屏尺寸、非法尺寸不产生 NaN。
- [ ] 在原生编译环境观察新测试先失败，再实现策略。
- [ ] 宽屏左列封面/信息/控制，右列歌曲队列/歌词；窄屏保留原布局和按钮标识。
- [ ] 原生全套单元测试和 iPhone/iPad UI 测试通过后提交。

### Task 2: 菜单、小播放器与窗口变化

**文件：** `AppShellView.swift`、`PlayerDockContainer.swift`、`MiniPlayerView.swift`、`LibraryView.swift`、布局策略测试。
**接口：** `AdaptivePlayerLayout.menuClearance(window: CGRect, menu: CGRect?, bottomInset: CGFloat) -> CGFloat`；底部菜单取实际高度与间隔，侧边/顶部菜单只保留安全底边。
- [ ] 先测底部菜单、侧边菜单、菜单消失和尺寸改变，避免过期 90 点间距。
- [ ] 新系统使用系统自适应标签导航；宽屏资料库分类改网格，不强制保持手机横向小卡片。
- [ ] 缩放时不重建播放模型，测当前歌曲与播放状态保持、详情收起后 mini 仍可点。
- [ ] 运行相关回归并提交。

### Task 3: 原生设备矩阵、真实素材与文档

**文件：** 新自适应验证工作流、设备选择脚本、UI 测试、截图捕获与素材清单、项目进度。
- [ ] Xcode 27.1 环境列出 SDK/模拟器，缺少 Duo 运行时则明确失败，不伪报验证通过。
- [ ] iPhone、iPad 13 英寸、Duo 上原生构建/测试与截图；旧 iPhone 回归不放宽。
- [ ] 真实页面验证后再生成四张 iPad 宣传图；先禁用旧两张的上传清单，防止工作流重新放回。
- [ ] 一次独立代码复核，修复关键问题；记录实际通过/等待/阻塞状态，提交推送；若只剩 GitHub 构建等待可结束本轮。
