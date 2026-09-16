# Building and running AquaRecover

This guide starts with a clean checkout and covers daily Flutter development,
Xcode, simulators, local test media, platform builds, and the checks used by the
repository. Commands are run from the repository root unless stated otherwise.

## Toolchain

CI currently uses Flutter 3.44.1 and Dart 3.12.1. A newer stable Flutter release
may work, but use the CI version when reproducing a build or test failure.

| Target | Required host tools |
| --- | --- |
| All targets | Git and Flutter 3.44.1 with Dart 3.12.1 |
| iOS and macOS | macOS, Xcode, Xcode command-line tools |
| Android | Android SDK, platform tools, build tools, and JDK 17 |
| Windows | Windows 10/11 and Visual Studio 2022 with **Desktop development with C++** |

[Install Flutter](https://docs.flutter.dev/install), then verify the host:

```bash
flutter --version
flutter doctor -v
```

Android Studio is optional. It is a convenient way to install the Android SDK
and create emulators, but AquaRecover can be built with Flutter, JDK 17, and the
Android command-line tools alone. Xcode is required for iOS and macOS builds.

macOS video export additionally looks for an `ffmpeg` executable already
installed on the machine. It is not bundled and is not required for photos.

## First checkout

```bash
git clone https://github.com/FinnGrndl/AquaRecover.git
cd AquaRecover
flutter config --no-analytics
flutter pub get
flutter devices
```

The platform projects are committed. Do not run `flutter create` over the
repository. The bootstrap script is only for intentionally regenerating all
platform folders; see [Regenerating platform projects](#regenerating-platform-projects).

## Run with Flutter

Flutter lists each target with a stable device ID:

```bash
flutter devices
```

Run the application on a selected target:

```bash
flutter run -d macos
flutter run -d <ios-simulator-id>
flutter run -d <android-device-id>
flutter run -d windows
```

While `flutter run` is attached, press `r` for hot reload, `R` for a full hot
restart, and `q` to stop. Use `--release` only when testing release performance;
debug mode provides the normal development loop.

Web and Linux are not declared application targets in `pubspec.yaml` and are not
part of the supported build matrix.

## iOS Simulator

### Boot and run a simulator

List the locally installed devices:

```bash
xcrun simctl list devices available
```

Choose a device UUID from that output. If it is shut down, boot it and open the
Simulator application:

```bash
AQUA_SIMULATOR_ID=<simulator-uuid>
xcrun simctl boot "$AQUA_SIMULATOR_ID"
open -a Simulator
flutter run -d "$AQUA_SIMULATOR_ID"
```

If the device is already marked `Booted`, skip the `simctl boot` command.

### Put photos and videos in the simulated Photos library

`simctl addmedia` imports host files into Photos without changing the repository:

```bash
xcrun simctl addmedia "$AQUA_SIMULATOR_ID" \
  "/absolute/path/to/dive-photo.jpg" \
  "/absolute/path/to/dive-video.mov"
```

For a reproducible first run, the repository includes the synthetic underwater
image used for its README screenshots:

```bash
xcrun simctl addmedia "$AQUA_SIMULATOR_ID" \
  "$PWD/docs/assets/demo-underwater-source.jpg"
```

It is documentation media, not a restoration-quality reference or algorithm
benchmark.

Open Photos in the simulator to confirm the import, then use **Choose from
Photos** in AquaRecover. Use an iPad simulator when testing the in-app PhotoKit
browser; iPhone uses the system picker.

To exercise the permission prompt again, reset only this app's simulated Photos
permission before launching it:

```bash
xcrun simctl privacy "$AQUA_SIMULATOR_ID" reset photos \
  io.github.finngrndl.aquarecover
```

Do not use `simctl privacy ... grant` while testing permission handling. A
forced grant can hide missing purpose strings or entitlement problems.

### Mount media directly into the simulator harness

The harness skips the first-run tutorial and can open files directly in the
editor. It expects them under `Documents/TestMedia` in the app data container.
Build and install the harness first:

```bash
AQUA_SIMULATOR_ID=<simulator-uuid>
AQUA_MEDIA_NAME=demo-underwater-source.jpg

flutter build ios --simulator --debug \
  -t tool/simulator_harness.dart \
  --dart-define=AQUA_TEST_MEDIA_NAMES="$AQUA_MEDIA_NAME"

xcrun simctl install "$AQUA_SIMULATOR_ID" \
  build/ios/iphonesimulator/Runner.app
```

Resolve the sandbox, create the harness directory, and copy the file:

```bash
AQUA_DATA_CONTAINER="$(xcrun simctl get_app_container \
  "$AQUA_SIMULATOR_ID" io.github.finngrndl.aquarecover data)"

mkdir -p "$AQUA_DATA_CONTAINER/Documents/TestMedia"
cp "/absolute/path/to/$AQUA_MEDIA_NAME" \
  "$AQUA_DATA_CONTAINER/Documents/TestMedia/$AQUA_MEDIA_NAME"

xcrun simctl launch "$AQUA_SIMULATOR_ID" \
  io.github.finngrndl.aquarecover
```

When using the bundled demo image, replace that `cp` command with:

```bash
cp docs/assets/demo-underwater-source.jpg \
  "$AQUA_DATA_CONTAINER/Documents/TestMedia/$AQUA_MEDIA_NAME"
```

For a batch, copy every file and pass a quoted pipe-separated list:

```bash
--dart-define='AQUA_TEST_MEDIA_NAMES=first.jpg|second.jpg|clip.mov'
```

The harness also accepts these compile-time flags:

| Define | Values | Effect |
| --- | --- | --- |
| `AQUA_OPEN_PHOTOS_PICKER` | `true` / `false` | Opens the Photos flow on launch |
| `AQUA_INITIAL_TOOL_GROUP` | `presets`, `light`, `crop`, `effects`, `video` | Opens Presets, Adjust, Crop, LUT, or Video |
| `AQUA_INITIAL_COMPARE_MODE` | `edited`, `original`, `split` | Chooses the initial preview mode |
| `AQUA_REVIEW_EXPORT_ON_START` | `true` / `false` | Opens export review after import |
| `AQUA_LIBRARY_ON_START` | `true` / `false` | Starts on the library screen |
| `AQUA_OPEN_LOCAL_EXPORTS_ON_START` | `true` / `false` | Opens the local export library directly |

Every `--dart-define` is compiled into the app. Rebuild after changing one.
Installing a different bundle identifier also changes the data-container lookup.

### Build and install without `flutter run`

```bash
flutter build ios --simulator --debug
xcrun simctl install "$AQUA_SIMULATOR_ID" \
  build/ios/iphonesimulator/Runner.app
xcrun simctl launch "$AQUA_SIMULATOR_ID" \
  io.github.finngrndl.aquarecover
```

This is useful for checking cold launch behavior without an attached Flutter
debug session.

### Capture simulator screenshots

Use `simctl` when a repeatable, full-resolution capture is preferable to the
Simulator menu:

```bash
xcrun simctl io "$AQUA_SIMULATOR_ID" screenshot \
  /tmp/aquarecover-screenshot.png
```

For consistent documentation captures, the simulator status bar can be fixed
temporarily and then restored:

```bash
xcrun simctl status_bar "$AQUA_SIMULATOR_ID" override \
  --time '9:41' \
  --dataNetwork wifi \
  --wifiMode active \
  --wifiBars 3 \
  --cellularMode notSupported \
  --batteryState charged \
  --batteryLevel 100

# Capture the required screens, then remove the override.
xcrun simctl status_bar "$AQUA_SIMULATOR_ID" clear
```

The screenshots in `docs/assets` were captured from the real app with this
workflow, not assembled as interface mockups.

## Xcode

Run `flutter pub get` before opening an Apple workspace so Flutter can generate
the local Swift packages and configuration files.

### iOS in Xcode

```bash
flutter pub get
open ios/Runner.xcworkspace
```

In Xcode:

1. Select the **Runner** scheme.
2. Choose an iOS simulator or connected iPhone.
3. Press **Run**.

Open the workspace, not `Runner.xcodeproj`; the workspace contains the Flutter
and plugin integration.

For a physical iPhone, unlock and trust the device, enable Developer Mode, and
select your Apple development team under **Runner > Signing & Capabilities**.
The committed bundle identifier belongs to AquaRecover, so outside contributors
will normally need a unique identifier such as `com.example.aquarecover.dev`.
No paid Apple Developer membership is required to run a development build on
your own device, although free provisioning has shorter validity and cannot be
used for App Store distribution.

The first device build can take longer while Xcode resolves packages and creates
a development provisioning profile.

### macOS in Xcode

```bash
flutter pub get
open macos/Runner.xcworkspace
```

Select **Runner**, choose **My Mac**, and press **Run**. Xcode is the preferred
way to test the first Photos permission request. macOS can attribute protected
resource requests to Terminal or VS Code when a debug process is launched from
there, causing a denial without an AquaRecover prompt. A standalone signed app
or an Xcode launch owns its permission request correctly.

If access was denied previously, use AquaRecover's **Open System Settings**
action or enable it under **System Settings > Privacy & Security > Photos**.

## Android

After installing the Android SDK and JDK 17, make sure Flutter can find them:

```bash
flutter config --android-sdk /absolute/path/to/Android/sdk
flutter doctor --android-licenses
flutter doctor -v
```

Start an emulator with Android Studio or `avdmanager`/`emulator`, or connect a
device with USB debugging enabled. Then run:

```bash
flutter devices
flutter run -d <android-device-id>
```

Create an installable debug APK with:

```bash
flutter build apk --debug
```

The output is `build/app/outputs/flutter-apk/app-debug.apk`. A local release APK
uses the generated debug key unless the four `ANDROID_KEYSTORE_*` environment
variables in `android/app/build.gradle.kts` are supplied. Never commit a
keystore or its passwords.

## Windows

Windows builds must run on Windows. Install Visual Studio 2022 and its **Desktop
development with C++** workload, then verify the setup:

```powershell
flutter config --enable-windows-desktop
flutter doctor -v
flutter pub get
flutter run -d windows
```

Build the release application with:

```powershell
flutter build windows --release
```

The application is written below `build\windows\x64\runner\Release`. The public
`.exe` installer is produced by CI with Inno Setup 6; day-to-day development
does not require Inno Setup.

## Build artifacts

Resolve packages once, then `--no-pub` makes repeated builds deterministic and
faster:

```bash
flutter pub get
flutter build apk --debug --no-pub
flutter build ios --simulator --debug --no-pub
flutter build ios --release --no-codesign --no-pub
flutter build macos --debug --no-pub
```

On Windows:

```powershell
flutter pub get
flutter build windows --debug --no-pub
```

Useful output locations:

| Build | Output |
| --- | --- |
| Android debug APK | `build/app/outputs/flutter-apk/app-debug.apk` |
| iOS Simulator app | `build/ios/iphonesimulator/Runner.app` |
| iOS device app | `build/ios/iphoneos/Runner.app` |
| macOS app | `build/macos/Build/Products/Debug/AquaRecover.app` |
| Windows app | `build\windows\x64\runner\Debug` |

`flutter build ios --release --no-codesign` verifies compilation but does not
produce a distributable IPA. App Store archives require an Apple distribution
certificate, matching provisioning profile, and App Store Connect access. The
maintainer release pipeline handles those credentials outside the repository.

## Tests and checks

Run the same source checks used by pull-request CI:

```bash
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
scripts/test_release_snapshot.sh
```

Relevant platform builds should also pass before a pull request is opened:

```bash
flutter build apk --debug --no-pub
flutter build ios --simulator --debug --no-pub
flutter build macos --debug --no-pub
```

Windows contributors should add `flutter build windows --debug --no-pub`.

### Optional private reference media

`test/img` is ignored by Git. It can hold numbered `before1.webp` / `after1.webp`
pairs, additional photos, and local videos for visual and performance work. The
repository and mandatory tests do not depend on those files.

```bash
dart run tool/evaluate_samples.dart
dart run tool/benchmark_processor.dart
dart run tool/tune_references.dart
```

Only use media you are permitted to store and process. Never put private test
media in a commit, issue, CI artifact, screenshot, or release package.

## Cleaning generated state

For ordinary dependency or build problems, start with:

```bash
flutter clean
flutter pub get
```

`flutter clean` removes generated build products, not source media. If Xcode
package resolution remains stale, close Xcode, run the commands above, and open
the workspace again.

## Regenerating platform projects

Most contributors never need this operation. `scripts/bootstrap_flutter_project.sh`
recreates Android, iOS, macOS, and Windows runners, then reapplies AquaRecover's
native bridges, identifiers, privacy manifests, entitlements, and branding
configuration.

Run it only from a clean feature branch and inspect every generated diff:

```bash
AQUA_ORG=com.yourname \
AQUA_APP_ID=com.yourname.aquarecover \
  ./scripts/bootstrap_flutter_project.sh
```

Afterward, regenerate and verify the platform icons:

```bash
dart run flutter_launcher_icons -f flutter_launcher_icons.yaml
git status --short
```

Do not use the bootstrap script merely to change a local signing team or select
a simulator.

## Related documentation

- [Project architecture](ARCHITECTURE.md)
- [On-device privacy](ON_DEVICE_PRIVACY.md)
- [Release automation](RELEASE_AUTOMATION.md)
- [Contributing](../CONTRIBUTING.md)
- [Flutter platform setup](https://docs.flutter.dev/platform-integration)
