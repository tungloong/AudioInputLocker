# InputSoundMenu

A small macOS menu bar app that mirrors the native Sound output popover for input devices.

## Build

```sh
xcodebuild -project InputSoundMenu.xcodeproj -scheme InputSoundMenu -configuration Debug build
```

## Behavior

- Shows a `Sound` menu bar extra with an input-volume slider.
- Lists Core Audio input devices.
- Selecting a row switches the system default input device.
- Devices that do not expose writable input volume keep the slider disabled.
