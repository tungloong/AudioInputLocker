# App Store Release Checklist

## App Store Connect

- Create a macOS app record for `AudioInputLocker`.
- Use bundle ID `com.tungloong.AudioInputLocker`, or replace it with the final
  explicit App ID registered in the Apple Developer account.
- Price: Free.
- Fill English and Simplified Chinese metadata from `docs/app-store/metadata.md`.
- Use `https://tungloong.github.io/AudioInputLocker/privacy.html` as the privacy
  policy URL.
- Set app privacy details to data not collected.

## Build Validation

- Build Debug and Release.
- Confirm the app bundle contains:
  - `AudioInputLocker.app`
  - App icon assets
  - `en.lproj/Localizable.strings`
  - `zh-Hans.lproj/Localizable.strings`
  - `PrivacyInfo.xcprivacy`
- Validate App Sandbox behavior on a real Mac:
  - Enumerate input devices.
  - Switch the default input device.
  - Read and write input volume when supported.
  - Restore the locked device after an external switch.
  - Reconnect a USB microphone.
  - Test AirPods auto-switching.

If sandboxing prevents the core input-switching behavior, use GitHub notarized
direct distribution instead of Mac App Store distribution.
