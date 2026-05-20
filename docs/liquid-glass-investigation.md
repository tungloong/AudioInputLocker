# Liquid Glass HUD Investigation

Date: 2026-05-18  
Project: `InputSoundMenu`  
Repository path: `/Users/tungloong/Documents/Codex/2026-05-15/macos-app-wi-fi-ui-app`

## Purpose

This document summarizes an unresolved visual issue in a macOS menu bar app: reproducing a small native-looking AirPods-style HUD using macOS 26 Liquid Glass.

The document is intended for cross-checking with other AI systems or engineers. It tries to separate observed facts, attempted implementations, SDK/runtime findings, and open questions.

## App Context

The app is a macOS menu bar utility for switching the system default audio input device.

Relevant behavior:

- The app can bind a preferred input device.
- When another process or system behavior changes the default input device away from the preferred device, the app switches it back.
- When this automatic switch-back occurs, the app shows a transient HUD.

Target visual reference:

- Apple's native AirPods / audio route HUD shown near the menu bar.
- The reference HUD uses the macOS 26 Liquid Glass visual language.
- Compared with typical blur/frosted materials, the reference HUD appears more transparent, more luminous, and has stronger edge/refraction behavior.

## The Current Problem

The current custom HUD can use Liquid Glass APIs, but the result does not visually match the native AirPods HUD closely enough.

Observed differences from the native HUD:

- The custom HUD looks less transparent.
- The custom HUD can look closer to frosted glass than the more luminous native HUD.
- Edge highlights and boundary treatment differ from the native HUD.
- The native HUD appears to use a stronger glass/refraction treatment than the public default Liquid Glass variants.
- Earlier light-mode tests showed mismatches between glass background adaptation and text legibility when the implementation mixed visual effect views, custom overlays, and fixed foreground colors.

The issue is specifically about the Liquid Glass material/effect, not the audio switching behavior. The input switching and preferred-device logic have been verified by the user as functionally working.

## Local Environment Observed

Build/runtime environment observed during development:

- macOS target: app deployment target is macOS 13.0, but Liquid Glass code is guarded with `#available(macOS 26.0, *)`.
- SDK used by local builds: `MacOSX26.4.sdk`.
- Swift compiler observed in tool output: Swift 6.3.
- Build command:

```sh
./scripts/build-and-run.sh
```

Build result after the latest Lab changes:

```text
BUILD SUCCEEDED
```

## Relevant Files

Current Liquid Glass experiment:

- `InputSoundMenu/LiquidGlassLab.swift`

Current menu entry for toggling the experiment:

- `InputSoundMenu/SoundMenuView.swift`

Current production HUD glass container:

- `InputSoundMenu/AudioInputViewModel.swift`

## Current Implementations

### Preferred Input HUD

The production HUD currently uses AppKit Liquid Glass on macOS 26:

```swift
@available(macOS 26.0, *)
private final class PreferredInputHUDLiquidGlassView: NSGlassEffectContainerView {
    private let glassView = NSGlassEffectView()
    private let glassContentView: PreferredInputHUDContentView

    private func setupGlass(size: NSSize) {
        spacing = 0
        wantsLayer = false
        glassView.frame = NSRect(origin: .zero, size: size)
        glassView.autoresizingMask = [.width, .height]
        glassView.cornerRadius = size.height / 2
        glassView.style = .clear
        glassView.tintColor = nil
        glassView.contentView = glassContentView

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.autoresizingMask = [.width, .height]
        container.addSubview(glassView)
        contentView = container
    }
}
```

Fallback path for older systems:

```swift
private final class PreferredInputHUDVibrantView: NSVisualEffectView {
    private func setupMaterial(size: NSSize) {
        material = .popover
        blendingMode = .behindWindow
        state = .active
        isEmphasized = false
        appearance = nil
        maskImage = Self.capsuleMaskImage(size: size)
    }
}
```

### Liquid Glass Lab

An isolated debug-only Lab window was created so that material experiments can be tested without coupling to the production HUD code.

Current Lab implementation:

```swift
@available(macOS 26.0, *)
private struct LiquidGlassLabAggressiveView: View {
    let size: NSSize

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            LiquidGlassLabContent()
                .frame(width: size.width, height: size.height)
                .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 38, style: .continuous))
        }
        .frame(width: size.width, height: size.height)
    }
}
```

The Lab is shown in a borderless nonactivating `NSPanel` with transparent background:

```swift
let panel = NSPanel(
    contentRect: centeredFrame(for: size),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
panel.backgroundColor = .clear
panel.hasShadow = true
panel.isOpaque = false
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
```

The Lab can be shown/hidden from a debug menu toggle:

```swift
#if DEBUG
LiquidGlassLabToggleRow()
#endif
```

## Attempts Made

### 1. NSVisualEffectView-based HUD

Implementation type:

- `NSVisualEffectView`
- Materials such as `.popover`
- Capsule mask image
- Custom SwiftUI-hosted content on top

Observed result:

- Produced a translucent/frosted HUD-like panel.
- Did not match the macOS 26 native AirPods HUD's stronger Liquid Glass effect.
- Light-mode behavior was problematic in some attempts: the material could adapt while fixed foreground colors did not, resulting in poor text contrast.

Status:

- Kept as fallback for older macOS versions.
- Not sufficient for matching the target macOS 26 HUD.

### 2. AppKit `NSGlassEffectView` with `.regular`

Implementation type:

- `NSGlassEffectContainerView`
- `NSGlassEffectView`
- `glassView.style = .regular`

Observed result:

- The result showed a real Liquid Glass effect.
- The visual was described by the user as a more conservative/frosted Liquid Glass appearance.
- It did not match the more transparent/luminous native AirPods HUD.

Status:

- Considered insufficient for the target visual.

### 3. AppKit `NSGlassEffectView` with `.clear`

Implementation type:

- `NSGlassEffectContainerView`
- `NSGlassEffectView`
- `glassView.style = .clear`
- `glassView.tintColor = nil`

Observed result:

- More transparent than `.regular`.
- Still did not match the native AirPods HUD closely enough.
- The user reported the custom HUD still looked less transparent than the native reference.

Status:

- Currently used by the production Preferred Input HUD on macOS 26.
- Still visually insufficient.

### 4. SwiftUI `GlassEffectContainer` + `.glassEffect(.clear.interactive())`

Implementation type:

- SwiftUI `GlassEffectContainer`
- `View.glassEffect(_:in:)`
- `Glass.clear`
- `Glass.interactive()`
- Continuous rounded rectangle shape

Observed result:

- This is the most aggressive implementation attempted so far using only public SwiftUI APIs.
- The user reported that it looked similar, but still not aggressive enough.

Status:

- Currently used by the debug Lab window.
- Not yet moved into the production HUD.
- Still does not fully match the native AirPods HUD.

## Public API Findings

### SwiftUI

From the macOS 26.4 SDK Swift interface, public `Glass` exposes:

```swift
@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
@available(visionOS, unavailable)
public struct Glass : Swift.Equatable, Swift.Sendable {
  public static var regular: SwiftUICore.Glass { get }
  public static var clear: SwiftUICore.Glass { get }
  public static var identity: SwiftUICore.Glass { get }
  public func tint(_ color: SwiftUICore.Color?) -> SwiftUICore.Glass
  public func interactive(_ isEnabled: Swift.Bool = true) -> SwiftUICore.Glass
}
```

Public custom glass modifier:

```swift
nonisolated public func glassEffect(
    _ glass: SwiftUICore.Glass = .regular,
    in shape: some Shape = DefaultGlassEffectShape()
) -> some SwiftUICore.View
```

Public glass container:

```swift
public struct GlassEffectContainer<Content> : SwiftUICore.View where Content : SwiftUICore.View {
  public init(spacing: CoreFoundation.CGFloat? = nil, @SwiftUICore.ViewBuilder content: () -> Content)
}
```

Public SwiftUI conclusion:

- Public custom glass variants appear limited to `regular`, `clear`, and `identity`.
- `tint` and `interactive` modify those variants.
- No public `controlCenter`, `notificationCenter`, `contentLensing`, or similar variant is visible in the Swift interface.

### AppKit

From `NSGlassEffectView.h` in the macOS 26.4 SDK:

```objc
typedef NS_ENUM(NSInteger, NSGlassEffectViewStyle) {
    /// Standard glass effect style.
    NSGlassEffectViewStyleRegular,
    /// Clear glass effect style.
    NSGlassEffectViewStyleClear
} API_AVAILABLE(macos(26.0)) NS_SWIFT_NAME(NSGlassEffectView.Style);
```

Public AppKit properties:

```objc
@interface NSGlassEffectView: NSView
@property (nullable, strong) __kindof NSView *contentView;
@property CGFloat cornerRadius;
@property (nullable, copy) NSColor *tintColor;
@property NSGlassEffectViewStyle style;
@end
```

Public AppKit conclusion:

- Public AppKit style choices are `regular` and `clear`.
- There is no public AppKit style named `controlCenter`, `notificationCenter`, `hud`, etc.

### NSVisualEffectView

Existing `NSVisualEffectView` materials include semantic materials such as:

- `.menu`
- `.popover`
- `.sidebar`
- `.headerView`
- `.sheet`
- `.windowBackground`
- `.hudWindow`
- `.fullScreenUI`
- `.toolTip`
- `.contentBackground`
- `.underWindowBackground`
- `.underPageBackground`

Observed limitation:

- These are older vibrancy/material APIs.
- They can produce blur/frosted effects, but they do not appear to reproduce the macOS 26 AirPods HUD Liquid Glass effect.

## Official Documentation References

Relevant Apple documentation and videos consulted:

- SwiftUI `Glass`: <https://developer.apple.com/documentation/swiftui/glass>
- SwiftUI custom Liquid Glass guide: <https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views>
- AppKit `NSGlassEffectView`: <https://developer.apple.com/documentation/AppKit/NSGlassEffectView>
- WWDC25 "Meet Liquid Glass": <https://developer.apple.com/videos/play/wwdc2025/219/>
- WWDC25 "Build an AppKit app with the new design": <https://developer.apple.com/videos/play/wwdc2025/310/>
- Apple HIG Materials: <https://developer.apple.com/design/human-interface-guidelines/materials>

Documentation-level interpretation:

- Public docs emphasize using system components where possible.
- For custom views, public API paths point to `Glass`, `glassEffect`, and `GlassEffectContainer`.
- Public docs do not expose the internal-looking variants found in the SDK binary symbol table.

## SDK and Runtime Findings

### SwiftUI binary symbols

The SwiftUI `.tbd` file contains symbols that are not visible as public Swift interface members.

Observed symbol names include:

```text
Material._GlassVariant.controlCenter
Material._GlassVariant.notificationCenter
Material._GlassVariant.contentLensing
Material._GlassVariant.boostWhitePoint
Material._GlassVariant.excludingOuterRefraction
Material._GlassVariant.highlightAngle
Material._GlassVariant.forceScrim
Material._GlassVariant.sharpTinting
Material._GlassVariant.bubbles
Material._GlassVariant.dock
Material._GlassVariant.widgets
Material._GlassVariant.appIcons
Material._GlassVariant.avplayer
Material._GlassVariant.facetime
```

Compile test:

```swift
import SwiftUI

@available(macOS 26.0, *)
func test() {
    _ = Material._experimentalGlass
    _ = Material._glassy(.controlCenter)
}
```

Observed compiler errors:

```text
type 'Material' has no member '_experimentalGlass'
type 'Material' has no member '_glassy'
cannot infer contextual base in reference to member 'controlCenter'
```

Interpretation:

- These symbols exist in the SDK binary export surface.
- They are not available through normal public Swift source usage.
- They appear to be private, SPI, or otherwise unavailable to third-party app source code.

### AppKit runtime properties

Runtime inspection of `NSGlassEffectView` found more properties than the public header exposes.

Observed Objective-C runtime property list:

```text
_variant
_subvariant
style
_interactionState
_subduedState
_scrimState
_contentLensing
_adaptiveAppearance
_useReducedShadowRadius
_groupIdentifier
clipsToBounds
tintColor
cornerRadius
_cornerConfiguration
_scrollPocketElementStyle
_path
contentView
_vibrantBlendingStyleForSubtree
_disableEmbeddingCount
_adaptationDebugDescription
```

Observed attributes:

```text
_variant Tq,N,V_variant
_subvariant T@"NSString",N,C
_interactionState Tq,N,V_interactionState
_subduedState Tq,N,V_subduedState
_scrimState Tq,N,V_scrimState
_contentLensing Tq,N,V_contentLensing
_adaptiveAppearance Tq,N,V_adaptiveAppearance
_useReducedShadowRadius TB,N,V_useReducedShadowRadius
_groupIdentifier T@"NSString",N,C
```

Observed default values:

```text
regular style -> _variant = 1
clear style   -> _variant = 2
```

For both styles, observed defaults included:

```text
_subvariant = nil
_contentLensing = 0
_scrimState = 0
_subduedState = 0
_interactionState = 0
_adaptiveAppearance = 2
_useReducedShadowRadius = 0
```

### AppKit private subvariant experiment

Runtime KVC accepted string values for `_subvariant`, including:

```text
regular
clear
controlCenter
notificationCenter
bubbles
dock
text
widgets
appIcons
avplayer
facetime
monogram
inspector
sidebar
carplayUltra
abuttedSidebar
focusBorder
```

Example runtime observation:

```text
controlCenter -> _subvariant = Optional(controlCenter)
notificationCenter -> _subvariant = Optional(notificationCenter)
```

Important caveats:

- This was runtime inspection only.
- These properties are not in the public header.
- No production implementation using these properties has been committed.
- Visual results of `_subvariant = "controlCenter"` have not yet been validated in the app UI.

### KVC numeric setters

Runtime tests indicated that several private numeric fields can be set through KVC:

```text
_variant: accepted 0...9 in simple tests
_contentLensing: accepted 0...9 in simple tests
_scrimState: accepted 0...9 in simple tests
_subduedState: accepted 0...9 in simple tests
_interactionState: accepted 0...2; 3+ failed
_adaptiveAppearance: accepted 0...2; 3+ failed
_useReducedShadowRadius: boolean-like
clipsToBounds: boolean-like
```

Important caveats:

- "Accepted" means the property could be set and read back in a simple runtime script.
- It does not mean the value is valid, supported, visually meaningful, or safe.
- Some invalid values caused runtime failures in exploratory scripts.
- These are private properties and should be treated as unstable.

## Hypotheses to Cross-check

These are not confirmed facts. They are candidate explanations for the observed visual gap.

### Hypothesis 1: Native AirPods HUD uses private glass variants

The native AirPods HUD may use internal variants such as:

- `controlCenter`
- `notificationCenter`
- `contentLensing`
- `boostWhitePoint`
- `excludingOuterRefraction`

Supporting observations:

- The names appear in SwiftUI binary symbols.
- Related-looking properties appear on `NSGlassEffectView` at runtime.
- Native system HUDs visually differ from public `regular` and `clear` outputs.

Unconfirmed:

- No direct inspection of the native AirPods HUD view hierarchy has confirmed these exact values.
- The native HUD may be implemented by a private framework rather than public AppKit/SwiftUI controls.

### Hypothesis 2: Public `clear` is not enough by itself

Public `Glass.clear` or `NSGlassEffectView.Style.clear` may only be one part of the effect.

Other factors may affect the native result:

- Window level and compositor treatment.
- Whether the window is created by a system process.
- Whether the view is in a special system overlay layer.
- Private subvariant values.
- Content lensing settings.
- Scrim/subdued/adaptive appearance settings.
- System accessibility settings.
- Desktop/window background colors behind the HUD.

Unconfirmed:

- It is not yet known which of these factors materially changes the result for third-party apps.

### Hypothesis 3: OS version affects Liquid Glass aggressiveness

The user noted that macOS 26.1 or 26.2 may have changed aggressive Liquid Glass behavior toward a more conservative look.

Observed in this project:

- The current environment uses SDK 26.4.
- The public API experiment still appears less aggressive than the native AirPods HUD.

Unconfirmed:

- No controlled comparison across macOS 26.0, 26.1, 26.2, 26.4 has been performed.
- No official Apple release note was found in this investigation that directly maps the visual difference to a public API behavior change.

## Implementation Constraints

Public/stable implementation constraints:

- Avoid private API for normal distribution.
- Avoid relying on KVC to set underscored properties in production code.
- Avoid fixed light/dark text colors that can become illegible when the glass material adapts.
- Preserve no-microphone-permission requirement; the app should remain an input switcher, not an audio recorder or monitor.

Experimental constraints:

- A debug-only Lab can test private or unstable values if clearly isolated.
- Any SPI/private experiment should be guarded and easy to remove.
- Visual validation is necessary because many private values can be set without obvious compile/runtime errors, but may not produce meaningful visual differences.

## Open Questions for External Review

1. Is there any public macOS 26 API beyond `Glass.regular`, `Glass.clear`, `Glass.tint`, `Glass.interactive`, `GlassEffectContainer`, and `NSGlassEffectView.Style` that controls stronger Liquid Glass refraction/lensing?

2. Is there a public way to request the same material variant used by Control Center, Notification Center, or the AirPods HUD?

3. Does `NSGlassEffectView` behave differently depending on:
   - `NSPanel` vs `NSWindow`
   - window level
   - collection behavior
   - shadow settings
   - `isOpaque`
   - `backgroundColor`
   - `NSHostingView` layer setup
   - whether content is inside `contentView`

4. Can a third-party app legitimately use any SPI related to:
   - `_subvariant`
   - `_contentLensing`
   - `_scrimState`
   - `_adaptiveAppearance`
   - `_variant`

5. If private API is acceptable for a self-use app, which `NSGlassEffectView` private property combinations most closely match:
   - AirPods route HUD
   - Control Center popovers
   - notification banners

6. Are there known macOS 26.1/26.2/26.4 behavioral changes to Liquid Glass that affect public `regular` or `clear` variants?

7. Is the native AirPods HUD using `NSGlassEffectView`, SwiftUI `Glass`, a private framework, or a compositor/system overlay not available to normal apps?

## Possible Next Experiments

These experiments have not yet been completed.

### Experiment A: Debug-only private AppKit subvariant matrix

Create a Lab-only `NSGlassEffectView` matrix with:

```swift
glassView.style = .clear
glassView.setValue("controlCenter", forKey: "_subvariant")
```

Test subvariants:

```text
controlCenter
notificationCenter
bubbles
dock
widgets
appIcons
avplayer
facetime
inspector
sidebar
```

Then test selected numeric properties:

```text
_contentLensing: 0, 1, 2
_scrimState: 0, 1, 2
_subduedState: 0, 1, 2
_adaptiveAppearance: 0, 1, 2
_interactionState: 0, 1, 2
```

Validation:

- Compare screenshots against native AirPods HUD in both light and dark modes.
- Verify text legibility.
- Verify edge highlight and transparency.
- Verify whether any values cause crashes or console warnings.

### Experiment B: Pure SwiftUI vs AppKit side-by-side

Render multiple Lab panels side-by-side:

- SwiftUI `.glassEffect(.regular)`
- SwiftUI `.glassEffect(.clear)`
- SwiftUI `.glassEffect(.clear.interactive())`
- AppKit `NSGlassEffectView.style = .regular`
- AppKit `NSGlassEffectView.style = .clear`
- AppKit private `_subvariant = "controlCenter"` if enabled

Validation:

- Same screen position.
- Same background.
- Same size and shape.
- Same text and icon content.

### Experiment C: Window/compositor matrix

Keep the glass view constant and vary:

- `NSPanel` vs `NSWindow`
- `.floating` vs `.statusBar` vs `.popUpMenu` levels
- `hasShadow`
- `isOpaque`
- `backgroundColor`
- `ignoresMouseEvents`
- `collectionBehavior`

Validation:

- Determine whether window configuration changes the compositor treatment.

## Current Objective State

Confirmed:

- Public Liquid Glass APIs work in the app.
- Public `.clear` and `.clear.interactive()` still do not visually match the native AirPods HUD according to user validation.
- Runtime inspection shows private `NSGlassEffectView` fields that correspond conceptually to more advanced glass behavior.
- Some private fields can be set via KVC in simple runtime tests.

Not confirmed:

- Whether private `_subvariant = "controlCenter"` reproduces the native AirPods HUD.
- Whether the native AirPods HUD uses `NSGlassEffectView`.
- Whether third-party apps can fully reproduce the native HUD using public APIs only.
- Whether OS version changes explain the difference.

Recommended cross-check focus:

- Verify whether public APIs are indeed limited to `regular` and `clear`.
- Verify whether there is an endorsed public route for Control Center / AirPods HUD material.
- Verify whether private `NSGlassEffectView` properties map to system Liquid Glass variants and whether any are viable for self-use tools.
