# Brand Assets / 品牌视觉

AudioInputLocker 的视觉方向是「安静、原生、可信赖」：它是一个常驻菜单栏的小工具，品牌需要在 App Store 图标里有辨识度，同时在菜单栏里保持克制。

## App Icon

![AudioInputLocker app icon](assets/audio-input-locker-app-icon-256.png)

图标概念是麦克风和锁的组合：麦克风代表系统输入设备，锁代表锁定并恢复偏好的默认输入。当前方向是白色玻璃底、白灰/珍珠色麦克风、暖古铜锁头，参考 macOS 26 Liquid Glass 系统图标的分层、霜化、透光边缘和克制高光，但刻意避免蓝色大底、强彩色渐变和旧式重拟物。App Icon 里的锁头允许和麦克风轻微重叠，并保留锁孔细节来增加可读性。

Asset paths:

- `docs/assets/audio-input-locker-app-icon.png`: 1024px master for README, store copy, and future exports.
- `AudioInputLocker/Assets.xcassets/AppIcon.appiconset`: compiled macOS app icon sizes.

Source prompt:

```text
Use case: logo-brand
Asset type: macOS app icon, square 1024x1024
Primary request: Create a refined macOS 26 / Liquid Glass style app icon for AudioInputLocker, a small macOS menu bar utility that locks the selected microphone input device.
Design direction: Native Apple system-app quality, quiet and premium, closer to macOS Tahoe / Liquid Glass than older skeuomorphic macOS icons. Use layered translucent glass, frostiness, lensing-like edge highlights, subtle specular highlights, gentle depth, and generous breathing room. Avoid heavy bevels, old metallic chrome, dark glossy badges, busy realism, and dated 2010-era gradients.
Subject: A centered, upright, front-facing microphone as the main symbol, clearly recognizable and optically balanced. The microphone should be made from warm white, pearl, soft gray, and translucent frosted-glass/ceramic layers, with rounded bold forms and a few clean grille slots. Add a lower-right padlock badge that is clearly a lock, simple and elegant, in muted antique bronze / warm brass glass material. Place the lock slightly inward from the extreme corner, allow subtle overlap with the microphone base, and include a small refined keyhole detail. The App Icon does not need to follow the single-color menu bar glyph; it can use full color, subtle transparency, and richer material layering.
Composition: Direct clean white / off-white rounded-square macOS app icon background, with very subtle layered glass panels, soft inner shadows, soft highlights, and no blue base. Keep the palette mostly white, ivory, pearl gray, silver gray, and muted bronze, with at most tiny restrained prismatic highlights from the glass.
Readability: Strong at small sizes, frontal not angled, simple silhouette, no music notes, no UI screenshot, no waveform, no excessive details.
```

## Menu Bar Icon

![AudioInputLocker menu bar icon preview](assets/audio-input-locker-menu-bar-preview.png)

菜单栏图标使用自定义 template image，而不是 SF Symbol。它有两种状态：普通状态只显示直立麦克风；锁定生效状态显示同一麦克风加右下角锁头。普通态的麦克风轴线对齐 18pt 画布中心；锁定态会切掉麦克风右下角，并在锁钩顶部额外留出透明避让区，为无锁孔的低矮锁身和倒 U 形锁钩留出独立空间。两套图标都只使用 alpha mask，让 macOS 自动处理浅色/深色菜单栏、选中态和高对比度显示。

Asset paths:

- `AudioInputLocker/Assets.xcassets/MenuBarIcon.imageset`: unlocked 18px, 36px, and 54px template PNGs.
- `AudioInputLocker/Assets.xcassets/MenuBarIconLocked.imageset`: locked 18px, 36px, and 54px template PNGs.
- `docs/assets/audio-input-locker-menu-bar-icon-source.svg`: editable unlocked source shape.
- `docs/assets/audio-input-locker-menu-bar-icon-locked-source.svg`: editable locked source shape.
- `docs/assets/audio-input-locker-menu-bar-icon-template.png`: larger transparent unlocked preview.
- `docs/assets/audio-input-locker-menu-bar-icon-locked-template.png`: larger transparent locked preview.

## Palette

- Warm White: `#F7F4EE` for the primary app icon surface.
- Soft Gray: `#D7D4CD` for microphone shadow and depth.
- Antique Bronze: `#A17A4A` for lock-specific emphasis.
- System Blue: `#0A84FF` for in-app selected state accents only.
- Frost: `#F8F8F6` for light backgrounds and App Store support art.
- Ink: `#1F2328` for documentation text and monochrome previews.

## Usage Rules

- Do use `MenuBarIcon` for the normal menu bar state and `MenuBarIconLocked` only when the lock is actively holding the current input device.
- Do keep the menu bar icon monochrome/template; do not ship a colored menu bar icon.
- Do keep the menu bar icon microphone-first, and keep the lock badge attached to the lower-right.
- Do avoid music-note-only symbols: the product is about audio input control, not music playback.
- Do keep app icon exports text-free so they remain legible at small sizes and App Store-safe.
- Do keep screenshots and store graphics quiet and native, with the menu popover and HUD as first-class visuals.

## References

- [Apple HIG: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [WWDC25: Say hello to the new look of app icons](https://developer.apple.com/videos/play/wwdc2025/220/)
- [WWDC25: Create icons with Icon Composer](https://developer.apple.com/videos/play/wwdc2025/361/)
- [WWDC25: Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)
