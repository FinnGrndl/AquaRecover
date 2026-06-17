# AquaRecover

AquaRecover is a cross-platform underwater photo and video color-restoration app for Android, iOS, and macOS. It is inspired by one-tap dive-footage restoration apps, but it is a clean implementation and is not affiliated with Dive+ or any other app.

The current build is now a more complete on-device prototype rather than the earlier MVP. Version 0.3.1 includes a second source-level bug/security audit pass. It has an Apple-style Cupertino interface with translucent glass panels, local Photos/File import, local processing, batch export, RAW still support, raw frame-stream support, LUT workflows, and privacy-first exports.

## What is implemented

### Apple-style interface

- `CupertinoApp`, `CupertinoSliverNavigationBar`, `CupertinoButton`, `CupertinoSlider`, `CupertinoSwitch`, and segmented controls.
- Translucent `GlassPanel` surfaces with blur and rounded hierarchy for an Apple/Liquid-Glass-like feel while remaining Flutter-native.
- Responsive layout for iPhone-size screens, large phones/tablets, and macOS windows.

### On-device media workflow

- Import from Files on Android, iOS, and macOS.
- Import from the local Photos library with multi-select and limited-library management.
- Save restored exports back to Photos when enabled.
- No cloud API, server upload, account login, or network backend is used by the app code.
- iCloud Photos may still download an original asset through the operating system before AquaRecover processes it locally.

### Photo restoration

- One-tap presets: Auto, Natural, Vivid reef, Deep dive, Macro, Shallow, Green water, Red filter, Artificial light, and Pro.
- Manual controls:
  - overall recovery,
  - red recovery,
  - auto white balance,
  - contrast stretch,
  - contrast,
  - saturation,
  - vibrance,
  - gamma,
  - hue,
  - brightness,
  - exposure,
  - highlights,
  - shadows,
  - black point,
  - haze reduction,
  - clarity,
  - sharpness,
  - vignette,
  - JPEG quality.
- Still-image pipeline:
  - red-channel compensation,
  - bounded gray-world white balance,
  - robust percentile contrast stretch,
  - gamma and tone controls,
  - vibrance/saturation,
  - hue rotation,
  - highlight/shadow/black-point controls,
  - optional vignette,
  - local unsharp/clarity pass.
- HEIC/HEIF decode routes through the native platform image bridge.

### Video restoration

- iOS video export uses the native AVFoundation/CoreImage bridge in `IosVideoProcessor.swift`.
- iOS still-image export and live still preview use the same native CoreImage image bridge when built with the bundled Runner sources.
- macOS video export is enabled only when a local `ffmpeg` command-line binary is available.
- Android builds keep photo recovery available and show a controlled "Video unavailable" state for video export.
- Optional trimming by start and end seconds before export.
- Optional audio retention; audio is transcoded to AAC for MP4 compatibility.
- Metadata stripping enabled by default.
- H.264 MP4 export with `+faststart` for easier sharing.
- Cancel control is only shown for running macOS `ffmpeg` video jobs; native/Dart exports ask the user to wait instead of pretending to cancel.
- Video before/after view by showing original and restored previews side by side.

### Batch processing

- Import multiple media items into a queue.
- Recover one selected item or process the entire queue.
- Per-item status: pending, processing, complete, failed.
- Clear completed items.

### RAW and pro workflows

- RAW stills on iOS/macOS use Core Image platform decoding and `CIRAWFilter` where available.
- Android DNG/platform-supported RAW decode uses the Android platform image decoder on Android 9/API 28+.
- Raw frame streams are supported by entering width, height, frame rate, and pixel format.
- Built-in LUT looks: Coral Warm, Blue Water, Green Water.
- Import `.cube` LUTs for still images and video exports.
- Nondestructive edit sidecar: every export writes a `.aquarecover.json` file next to the output with settings, trim, LUT, and export options.

### Export and privacy controls

- Export presets:
  - **Social**: JPEG, lower size, strips metadata.
  - **Archive**: high-quality JPEG, preserves metadata setting by preset.
  - **Pro edit**: PNG still export, maximum still quality settings.
- Manual JPEG/PNG still export selection.
- Metadata strip toggle.
- Save-to-Photos toggle.
- Keep-video-audio toggle.
- Output filenames are sanitized and length-limited.
- Decoded image and RAW video dimensions are bounded to reduce resource-exhaustion risk.

## Important limitations

- This repository is a source prototype. It still needs local Flutter/Xcode validation before App Store or Play Store distribution.
- Before distribution, run `flutter analyze`, `flutter test`, `flutter build ios --profile --no-pub`, and `flutter build macos --debug --no-pub` on the target machine. Android builds require a local Android SDK.
- The latest audit fixed duplicate Apple `RawBridge` definitions, temporary RAW/HEIC intermediate cleanup, Photos import error recovery, stricter trim parsing, full RAW pixel-format selection, native iOS video/image bridge bootstrapping, and idempotent bootstrap insertion logic.
- The fast live preview uses a native iOS CoreImage path when available and a bounded Dart isolate fallback elsewhere. Final still exports use full-resolution native iOS rendering or the guarded Dart isolate fallback.
- Custom `.cube` LUT intensity is fully respected for still images. macOS video export applies the generated FFmpeg filter chain when the optional `ffmpeg` CLI backend is present.
- Generic raw frame streams are supported. Proprietary RAW video such as Blackmagic RAW, REDCODE RAW, and ProRes RAW needs vendor/platform SDK and licensing review.
- The bundled `ffmpeg_kit_flutter_new` dependency was removed because its Apple binaries introduced absolute Homebrew dylib references and blocked Apple-Silicon iOS Simulator builds. Reintroduce bundled video processing only after licensing and packaging review.
- Android still uses the demo `com.example.aqua_recover` package ID and debug signing for release builds. Change `namespace`, `applicationId`, and signing config before publishing an APK/AAB.

## Mac setup

### 1. Install Xcode

Install Xcode from the Mac App Store, then run:

```bash
sudo sh -c 'xcode-select -s /Applications/Xcode.app/Contents/Developer && xcodebuild -runFirstLaunch'
```

Open Xcode once and accept license prompts. Install any missing iOS runtime components if Xcode asks.

### 2. Install Flutter

Install the latest stable Flutter SDK for macOS, add `flutter/bin` to your shell path, then verify:

```bash
flutter --version
flutter doctor -v
```

Enable/precache Apple platform support:

```bash
flutter config --enable-macos-desktop
flutter precache --ios --macos
```

### 3. Unzip and bootstrap the generated platform folders

```bash
unzip aqua_recover_on_device_full_audited.zip
cd aqua_recover
```

For local testing with the default package ID:

```bash
./scripts/bootstrap_flutter_project.sh
```

For iPhone testing, use your own reverse-domain ID so Apple signing can create a unique App ID:

```bash
AQUA_ORG=com.yourname ./scripts/bootstrap_flutter_project.sh
```

The script:

- runs `flutter create` for Android, iOS, and macOS,
- sets Android `minSdk` to 24,
- sets iOS deployment target to 14.0,
- adds Android media permissions,
- copies native Android/iOS/macOS RAW/image/video bridge files,
- adds iOS native `RawBridge.swift` and `IosVideoProcessor.swift` to the Xcode project,
- adds iOS/macOS Photos usage strings,
- adds macOS Photos and user-selected-file entitlements,
- copies the privacy manifest files,
- runs `flutter pub get`.

### 4. Run checks locally

```bash
flutter clean
flutter pub get
flutter analyze
flutter test
```

### 5. Run on your Mac

```bash
flutter run -d macos
```

Then:

1. Click **Import Files** or **Import from Photos**.
2. Pick a photo/video/RAW file.
3. Choose a one-tap look or tune sliders.
4. Recover the selected item or the whole queue.
5. Find exports in the app's Documents/AquaRecover Exports folder. Each export also gets a `.aquarecover.json` sidecar.

## Test on a physical iPhone

### 1. Connect and trust the phone

1. Connect the iPhone to your Mac by USB.
2. Unlock the iPhone.
3. Tap **Trust This Computer** if prompted.
4. Keep the phone unlocked while Xcode pairs with it.

### 2. Enable Developer Mode

On iOS 16 or later, Developer Mode may only appear after you first try to run from Xcode.

1. Open Xcode.
2. Open **Window > Devices and Simulators** and pair the iPhone if needed.
3. Select the connected iPhone as a run destination once.
4. On the iPhone, open **Settings > Privacy & Security > Developer Mode**.
5. Turn Developer Mode on.
6. Restart the iPhone when prompted and confirm Developer Mode after restart.

### 3. Configure signing

```bash
open ios/Runner.xcworkspace
```

In Xcode:

1. Select the **Runner** project.
2. Select the **Runner** target.
3. Open **Signing & Capabilities**.
4. Enable **Automatically manage signing**.
5. Select your Apple team or personal team.
6. Set a unique **Bundle Identifier**, for example `com.yourname.aquarecover`.
7. Select your connected iPhone as the run destination.
8. Click **Run** once from Xcode.

After Xcode creates signing assets, you can usually run from Terminal:

```bash
flutter devices
flutter run -d <your-iphone-device-id>
```

### 4. Test the app on iPhone

1. Open AquaRecover.
2. Tap **Import from Photos** and grant selected or full Photos access.
3. Select several underwater photos or videos.
4. Try **Auto**, **Deep dive**, **Green water**, and **Artificial light** presets.
5. Tune sliders and verify the live preview for still images.
6. For video, set trim start/end seconds, then export.
7. Enable **Save exports to Photos** to verify the Photos write flow.
8. Check the exported result and sidecar JSON in the app documents folder if testing through Finder/device logs.

## On-device processing architecture

```text
Import from Files / Photos
        |
        v
Local app sandbox or OS-provided local asset file
        |
        +--> Still image decode/restoration in native iOS CoreImage
        |       or guarded Dart isolate fallback
        |       or native HEIC/RAW decode bridge
        |
        +--> Native iOS video processing through AVFoundation/CoreImage
        |
        +--> Optional macOS video/raw frame processing through local ffmpeg CLI
        |
        v
Underwater restoration settings + optional LUT
        |
        v
Local export file + nondestructive .aquarecover.json sidecar
        |
        +--> Optional local Photos-library save
```

No app code sends media to a remote endpoint. Keep in mind that OS services such as iCloud Photos may retrieve a cloud-backed original before handing a local file to the app.

## Project layout

```text
lib/
  core/
    media/                 file classification
    models/                settings, export options, media jobs, raw video descriptor
    persistence/           nondestructive sidecar writer
    photo/                 Photos-library import/save service
    platform/              Flutter method-channel image/RAW bridge
    processing/            image, video, and LUT restoration services
    utils/                 output file paths
  features/editor/         Cupertino editor UI and previews
platform_overrides/        native Android/iOS/macOS files copied after flutter create
native/libraw_bridge/      optional LibRaw C ABI scaffold
docs/                      architecture, audit, privacy, and roadmap notes
scripts/                   bootstrap helper
```

## Troubleshooting

### `Flutter SDK is required`

Install Flutter and confirm the command works:

```bash
flutter --version
```

### iPhone does not appear in `flutter devices`

Run:

```bash
open -a Xcode
open ios/Runner.xcworkspace
```

Then check **Window > Devices and Simulators**. Pair the phone, trust the Mac on the phone, and enable Developer Mode.

### Xcode signing fails

Use a unique bundle identifier in **Runner > Signing & Capabilities**. Personal-team signing can run local builds on your device but is not the same as App Store distribution.

### Photos import fails on macOS

Make sure the generated macOS target has the Photos entitlement and usage string. The bootstrap script copies these from `platform_overrides/macos/Runner` and injects `NSPhotoLibraryUsageDescription` into `macos/Runner/Info.plist`.

### Build fails after changing `AQUA_ORG`

Delete generated platform folders and bootstrap again:

```bash
rm -rf android ios macos
AQUA_ORG=com.yourname ./scripts/bootstrap_flutter_project.sh
```

### Native iOS video or image export says the backend is missing

Make sure the generated iOS project contains both native bridge files:

```text
ios/Runner/RawBridge.swift
ios/Runner/IosVideoProcessor.swift
```

If either file is missing after a fresh `flutter create`, rerun:

```bash
./scripts/bootstrap_flutter_project.sh
flutter clean
flutter pub get
flutter build ios --profile --no-pub
```

### HEIC or RAW import fails

HEIC/HEIF and RAW decoding depends on platform codec support. Test the same file in Preview/Photos on macOS or iOS first. For broader DSLR/mirrorless RAW coverage, wire up the optional LibRaw bridge and review its distribution terms.
