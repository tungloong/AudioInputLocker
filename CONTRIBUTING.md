# Contributing

Thanks for helping improve AudioInputLocker.

Please keep discussion respectful and practical. See `CODE_OF_CONDUCT.md` for
the short project conduct note.

## Development Setup

Requirements:

- macOS 13.0 or later for runtime testing.
- Xcode with the macOS 26 SDK for building the current source.

Use the local build helper:

```sh
./scripts/build-and-run.sh
```

Manual build:

```sh
xcodebuild \
  -project AudioInputLocker.xcodeproj \
  -scheme AudioInputLocker \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData \
  build
```

For changes that affect lock behavior, please test at least one real input
device switching scenario, such as AirPods auto-switching, System Settings
changes, or USB microphone reconnects.

## Pull Requests

- Keep changes focused and easy to review.
- Preserve the native macOS feel of the menu and HUD.
- Update both English and Simplified Chinese user-facing strings when adding UI
  copy.
- Update README or docs when behavior, requirements, privacy notes, or release
  steps change.
- Mention any manual device-switching scenarios you tested.

## Localization

User-facing strings live in:

- `AudioInputLocker/en.lproj/Localizable.strings`
- `AudioInputLocker/zh-Hans.lproj/Localizable.strings`

Please keep the keys aligned between both files.

## Privacy And Networking

AudioInputLocker is intended to stay local-first. Do not add analytics,
telemetry, accounts, or network calls without opening an issue first and
updating the privacy documentation.

## Git Hygiene

- Do not commit `build/`, DerivedData, archives, local Xcode user data, or
  personal environment files.
- Keep generated visual assets in `docs/assets` and app-shipped assets in
  `AudioInputLocker/Assets.xcassets`.
