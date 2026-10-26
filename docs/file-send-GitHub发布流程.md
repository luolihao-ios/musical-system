# file send 的 GitHub 发布与商店管理

互传 App 的原始身份仍是 `com.luolihao.aiyuetransfer`，与音乐播放器的 `com.luolihao.musicalsystem` 分开校验。商店名称与安装后显示名称采用 `file send`。三语言副标题由 `scripts/filesend_store.py` 管理。

现有 `.github/workflows/aiyue-next-release.yml` 提供手动操作：

- `inspect-store`：读取互传 App、可编辑商店版本、名称与最新构建，保存回读文件。
- `update-store`：更新唯一可编辑 App 信息中的简体中文、繁体中文和英文名称、副标题，逐字段回读。
- `capture`：使用 Xcode 27.1 和真实 iPhone、iPad、Duo 模拟器运行生产界面，截取连接、接收、发送、编辑、完成五页及横屏证据。
- `verify`：三设备测试后归档并导出签名 IPA，保存构建产物。
- `release`：执行上述验证、编译、归档、签名、打包和 TestFlight 上传。
- `upload-assets`：使用 `marketing/file-send-2026-10-26/文件验收清单.json` 上传素材库，并绑定到互传 App 的可编辑简体中文版本；同名同内容重复执行不会再次上传。

普通 push 只验证与打包。TestFlight 上传由明确调用 `release` 触发。营销版本沿用 `1.0.1`，打包前读取该 App 全部构建号，在最大整数构建号上增加一，避免重复上传 `110`。归档步骤显式覆盖构建号，不改变营销版本。

所有 Apple 密钥和签名资料均读取 GitHub 现有 Secrets。流水线不会提交 App Store 审核，也不会发布正式版本。

素材必须以通过三设备验证的原生截图为界面依据。五张 iPhone 宣传图、四张 Duo、四张 iPad，以及独立页首图与搜索结果图应通过尺寸、RGB 不透明格式和 SHA-256 校验后再进入上传清单。云端产物 `filesend-adaptive-device-captures` 保留原始截图和测试结果；`filesend-store-verification` 保留商店操作前资料及回读结果。
