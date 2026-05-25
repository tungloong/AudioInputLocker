# FAQ And Troubleshooting

## English

### Does AudioInputLocker record audio?

No. AudioInputLocker does not record, process, upload, or analyze microphone
audio. It uses Core Audio to list input devices, switch the system default input
device, read/write input volume when supported, and observe device changes.

### Why does a device have no volume slider?

Some input devices do not expose a writable input-volume control through Core
Audio. AudioInputLocker shows the slider only when macOS reports that the device
supports it.

### Does lock mode work with AirPods and USB microphones?

It is designed for that workflow. When the locked device is online and another
process changes the default input, AudioInputLocker switches back to the locked
device. Behavior can still vary by device firmware and macOS routing rules.

### Does the app need microphone permission?

The app does not record audio, so it is not expected to request microphone
recording permission. It manages device selection through Core Audio.

### Why does macOS warn about the preview download?

The current GitHub preview build is not notarized. Build from source or wait for
a notarized/App Store release if you prefer the normal Gatekeeper path.

### What should I include in a bug report?

Include your macOS version, Mac model, app version or commit, involved audio
devices, steps to reproduce, expected behavior, and actual behavior.

## 简体中文

### AudioInputLocker 会录音吗？

不会。AudioInputLocker 不会录制、处理、上传或分析麦克风音频。它只使用
Core Audio 列出输入设备、切换系统默认输入、在设备支持时读写输入音量，并监听设备变化。

### 为什么某些设备没有音量滑杆？

有些输入设备没有通过 Core Audio 暴露可写的输入音量控制。只有 macOS 报告该设备支持时，AudioInputLocker 才会显示滑杆。

### 锁定模式支持 AirPods 和 USB 麦克风吗？

这是它主要想解决的场景之一。当锁定设备在线，并且其他进程改变默认输入设备时，AudioInputLocker 会切回锁定设备。实际表现仍可能受设备固件和 macOS 路由规则影响。

### app 需要麦克风权限吗？

app 不录音，因此正常情况下不需要请求麦克风录制权限。它通过 Core Audio 管理设备选择。

### 为什么 macOS 会警告 GitHub preview 下载？

当前 GitHub preview build 尚未 notarize。你可以从源码构建，或者等待后续 notarized / App Store 版本。

### 报 bug 时应该提供什么？

请提供 macOS 版本、Mac 机型、app 版本或 commit、相关音频设备、复现步骤、预期行为和实际行为。
