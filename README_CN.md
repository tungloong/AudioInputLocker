# AudioInputLocker

<p align="center">
  <img src="docs/assets/audio-input-locker-app-icon-256.png" width="112" alt="AudioInputLocker app icon">
</p>

[English](README.md) | [简体中文](README_CN.md)

AudioInputLocker 是一个用于管理 macOS 系统默认音频输入设备的小型菜单栏 app。

macOS 已经有一个原生风格的声音输出菜单，但没有一个同样顺手的麦克风和输入设备菜单。AudioInputLocker 补上了这块空白：它提供一个接近系统声音菜单的输入设备菜单，并加入锁定模式，在 macOS 或其他 app 尝试切走输入设备时，自动切回你偏好的设备。

## 功能

- 原生 macOS 风格的菜单栏声音输入弹窗。
- 列出 Core Audio 输入设备。
- 可以从菜单直接切换系统默认输入设备。
- 当设备暴露可写输入音量时，显示并控制输入音量。
- 可以锁定偏好的输入设备，并在外部变更后自动恢复。
- 使用 `UserDefaults` 在 app 重启后保留锁定设备。
- 锁定设备离线后仍保留在锁定区域，方便 USB 麦克风或耳机重新连接后继续沿用用户意图。
- 当 app 自动恢复锁定输入设备时显示短暂 HUD。
- 支持英文和简体中文，并跟随系统语言。

## 系统要求

- 运行环境：macOS 13.0 或更新版本。
- 构建环境：带 macOS 26 SDK 的 Xcode。

App 的部署目标是 macOS 13.0。HUD 会在可用时使用公开的 macOS 26 Liquid Glass API，并在旧系统上使用回退实现。

## 构建与运行

使用本地辅助脚本：

```sh
./scripts/build-and-run.sh
```

这个脚本会构建 Debug app，停止正在运行的 `AudioInputLocker` 进程，然后从 `build/DerivedData` 打开新构建的 app。

手动构建：

```sh
xcodebuild \
  -project AudioInputLocker.xcodeproj \
  -scheme AudioInputLocker \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData \
  build
```

如果不是 Apple Silicon 目标，可以在运行脚本时覆盖 `DESTINATION`。

## 使用方式

1. 启动 app。
2. 点击菜单栏里的麦克风图标。
3. 选择一个输入设备，将它设为系统默认输入。
4. 打开 `锁定输入设备`，并选择你希望保持激活的设备。

开启锁定模式后，AudioInputLocker 会监听 Core Audio 设备变化。如果其他进程、系统设置、AirPods 自动切换或命令行工具改变了默认输入设备，只要锁定设备在线，app 就会自动切回它。

## 本地化

App 当前包含：

- 英文：`AudioInputLocker/en.lproj/Localizable.strings`
- 简体中文：`AudioInputLocker/zh-Hans.lproj/Localizable.strings`

设备名称来自 Core Audio，会按照 macOS 或设备本身提供的名称显示。

## 项目结构

- `AudioInputLocker/AudioInputLockerApp.swift`：app 入口和菜单栏 extra。
- `AudioInputLocker/SoundMenuView.swift`：声音风格的菜单弹窗。
- `AudioInputLocker/AudioInputViewModel.swift`：app 状态、锁定行为、Core Audio 编排和 HUD 实现。
- `AudioInputLocker/CoreAudioInputManager.swift`：Core Audio 封装。
- `AudioInputLocker/InputDevice.swift`：输入设备模型和图标推断逻辑。
- `AudioInputLocker/HUDMicrophone.png`：HUD 麦克风资源。
- `AudioInputLocker/Assets.xcassets`：app 图标和菜单栏图标资源目录。
- `scripts/build-and-run.sh`：本地构建和重启辅助脚本。
- `docs/brand.md`：品牌视觉和图标使用说明。
- `docs/github-release.md`：GitHub 仓库设置说明。
- `docs/app-store`：App Store metadata、隐私政策和发布检查清单。
- `docs/liquid-glass-investigation.md`：HUD 视觉实验的历史记录。

## 实现说明

AudioInputLocker 使用 SwiftUI、AppKit 和 Core Audio 构建。

- app 是菜单栏工具，并通过 `LSUIElement` 隐藏 Dock 图标。
- Core Audio 用于设备枚举、默认输入切换、输入音量读写和设备变化监听。
- 锁定状态保存在本地 `UserDefaults`。
- 已加入 App Sandbox entitlements，用于 Mac App Store 验证。
- HUD 是一个位于 status-bar level 的 `NSPanel`，可以靠近菜单栏显示，同时不抢占普通 app 焦点。
- app 不使用私有 API。

## 隐私

AudioInputLocker 只在你的 Mac 本地工作。它不包含分析统计、网络请求、账号系统或遥测。

## 已知后续事项

- 归档上传前，在 Apple Developer 账号中注册最终 explicit App ID 和 Team。
- App Store 提交前，将隐私政策发布到公开 URL。
- 准备英文和简体中文 App Store 截图。
- 增加发布打包、签名、notarization 和上传自动化流程。
- 继续对照 macOS 原生 route HUD 微调 HUD 视觉效果。
- 随着锁定状态机和 HUD 继续演进，拆分 `AudioInputViewModel.swift`。
- 在可行范围内为锁定状态机补充自动化测试。

## 贡献

欢迎 issue 和 pull request。请保持改动聚焦，并尽量保留菜单和 HUD 的原生 macOS 质感。项目约定见 `CONTRIBUTING.md` 和 `SECURITY.md`。

提交 pull request 前，建议先运行：

```sh
./scripts/build-and-run.sh
```

如果改动影响锁定行为，也请至少测试一个真实设备切换场景，例如 AirPods 自动切换、系统设置切换或 USB 麦克风重连。

## 许可证

AudioInputLocker 使用 MIT License 发布。详见 `LICENSE`。
