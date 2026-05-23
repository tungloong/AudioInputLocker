# Contributing

Thanks for helping improve AudioInputLocker.

## Development

Use the local build helper:

```sh
./scripts/build-and-run.sh
```

For changes that affect lock behavior, please test at least one real input
device switching scenario, such as AirPods auto-switching, System Settings
changes, or USB microphone reconnects.

## Pull Requests

- Keep changes focused and easy to review.
- Preserve the native macOS feel of the menu and HUD.
- Update both English and Simplified Chinese user-facing strings when adding UI
  copy.
- Mention any manual device-switching scenarios you tested.

## Localization

User-facing strings live in:

- `AudioInputLocker/en.lproj/Localizable.strings`
- `AudioInputLocker/zh-Hans.lproj/Localizable.strings`
