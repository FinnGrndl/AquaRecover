<p align="center">
  <img src="assets/branding/aquarecover_app_icon.png" width="124" alt="AquaRecover app icon">
</p>

<h1 align="center">AquaRecover</h1>

<p align="center">
  <strong>An open-source, on-device darkroom for underwater images.</strong><br>
  Recover color, rebuild contrast, inspect every change, and keep the original untouched.
</p>

<p align="center">
  <a href="https://github.com/FinnGrndl/AquaRecover/actions/workflows/ci.yml"><img src="https://github.com/FinnGrndl/AquaRecover/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
  <a href="https://github.com/FinnGrndl/AquaRecover/releases/latest"><img src="https://img.shields.io/github/v/release/FinnGrndl/AquaRecover?display_name=tag&sort=semver&label=release" alt="Latest AquaRecover release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/FinnGrndl/AquaRecover" alt="MIT License"></a>
  <a href="https://github.com/FinnGrndl/AquaRecover/releases/latest"><img src="https://img.shields.io/github/downloads/FinnGrndl/AquaRecover/total?label=downloads" alt="Release downloads"></a>
</p>

## Underwater light is the problem

A camera does not see the same scene below the surface that it would see in
air. Water absorbs warm wavelengths first. Reds and oranges disappear with
distance, blue or green begins to dominate, haze lowers local contrast, and
artificial light can produce a completely different color balance a few
centimeters away.

A global white-balance correction can move the whole image toward neutral, but
it cannot describe all of that. Push it too far and open water turns magenta;
hold it back and the diver, reef, or wreck never regains warmth.

AquaRecover treats the photo as an underwater scene rather than a badly chosen
color temperature. It measures channel loss and luminance, estimates how much
warm color can safely return, separates open water from textured subjects, and
rebuilds tone before applying the familiar editing controls. The automatic
result is a starting point, not a locked decision.

Everything happens locally. There is no account, upload queue, analytics SDK,
subscription, or remote processing service.

<p align="center">
  <img src="docs/assets/editor-split.webp" width="31%" alt="AquaRecover editor showing the original and restored underwater image side by side">
  <img src="docs/assets/editor-crop.webp" width="31%" alt="AquaRecover crop editor with draggable crop frame and rotation controls">
  <img src="docs/assets/export-review.webp" width="31%" alt="AquaRecover export review with format and destination controls">
</p>

<p align="center"><sub>Real iOS Simulator captures using the repository's synthetic demo image. No third-party dive photo is redistributed.</sub></p>

## From dive to export

```text
Photos or Files
      ↓
scene measurement → bounded color recovery → tone and local contrast
      ↓
preset baseline → manual adjustments → crop / rotate / LUT
      ↓
edited, original, or split comparison
      ↓
Photos, Files, or the local AquaRecover library
```

Select one photo and AquaRecover opens it in the editor as soon as the initial
preview is ready. Select several and the same action becomes a batch: every
item keeps its own edit state, settings can be copied from one frame to selected
or all others, and completed exports leave the queue so they cannot be exported
twice by accident.

Presets describe a complete starting profile. They have their own strength
control and remain the baseline for later edits. Tapping an adjustment value
restores only that control to the value supplied by the preset. The **None**
preset is deliberately neutral and leaves the image unchanged.

The editor keeps comparison close to the image. Switch between edited and
split views, press and hold to reveal the original, fit the complete frame or
fill the preview, and pinch to inspect details. Cropping is nondestructive and
supports fixed or freeform ratios, draggable edges and corners, rotation,
straightening, and flips. A dedicated LUT tab accepts built-in looks and custom
`.cube` files for still images.

Nothing is written when media is imported. Output is created only after export
is confirmed, and each destination is independent:

- add the result to the system Photos library;
- save it to a folder chosen with the system file picker;
- keep it in AquaRecover's local export library;
- or combine those destinations.

Local exports receive a small `.aquarecover.json` sidecar with the edit,
transform, LUT, and export settings. It records file names, not the original
absolute path.

## What happens to a pixel

The default processor is deterministic and inspectable. It does not use a
trained model, invent scene content, or send an image elsewhere.

### It does not cut the image into objects

AquaRecover never labels a region as *diver*, *reef*, *sand*, or *water*.
Instead, it calculates several continuous weights between `0` and `1` for every
pixel. A pixel can look partly like open water and partly like textured
material, and neighboring pixels can move gradually between those states. This
avoids the hard halos that a binary mask would leave around fins, bubbles, fish,
and coral.

### 1. Build one profile for the scene

The portable renderer samples the image on an adaptive grid and builds red,
green, blue, and luminance histograms. From those samples it keeps:

- the mean of each color channel;
- the 1st and 99.5th luminance percentiles as robust black and white points;
- the 10th luminance percentile as an estimate of scene depth and darkness;
- red-to-green and blue-to-green ratios as indicators of red loss and water
  color.

The channel means produce bounded gray-world gains. For example, the red gain
may move only between `0.75` and `2.05`; green is limited to `0.82`–`1.28`, and
blue receives a separate bound depending on whether the scene is blue- or
green-dominant. These limits stop a single unusual color from driving the
entire correction.

### 2. Calculate soft water and material weights

For each source pixel, the processor first measures how far red lies below the
stronger of green and blue. In simplified form, the open-water weight is:

```text
red deficit     = clamp((max(G, B) - R) / 165)
blue dominance  = clamp((B - R) / 180)
green dominance = clamp((G - R) / 180)
chroma          = clamp((max(R, G, B) - min(R, G, B)) / 140)

water = clamp(red deficit
              × (0.58 × blue dominance + 0.42 × green dominance)
              × chroma)
```

Here, `clamp` means limiting a value to `0…1`, and `mix(a, b, t)` means linear
interpolation from `a` to `b` by weight `t`. This is a color likelihood, not
semantic recognition: a value of `0.7` feeds the later water-protection blends
at that strength, while each rule still applies its own coefficient and limit.

A second weight looks for recoverable cyan material. It combines the same red
deficit with brightness and reduces the result as the water weight rises:

```text
brightness           = clamp((luminance - 42) / 132)
recoverable material = red deficit × brightness
                       × clamp(1 - 0.52 × water, 0.18, 1)
```

That weight lets a lit subject regain neutral color while keeping flat blue or
green backgrounds from becoming red.

### 3. Measure structure at three scales

After the first color and tone pass, AquaRecover creates a smaller guide image:
its longest side is at most 420 pixels for export and 180 for a preview. Three
blur radii, derived from roughly `1/70`, `1/36`, and `1/18` of the short side,
describe fine, medium, and broad illumination changes.

Subtracting each blurred value from local luminance produces detail residuals.
Their magnitudes form a **structure weight**; a weighted combination of all
three forms **local contrast**:

```text
structure      = clamp(5.5 × |fine detail| + 3.0 × |medium detail|)
local contrast = clamp(0.12 × fine + 0.32 × medium + 0.56 × broad)
```

The guide also stores broadly blurred red, green, and blue values. Each
full-resolution pixel reads the corresponding guide sample, so changes remain
smooth across an area instead of reacting independently to sensor noise.

### 4. Blend a correction, rather than replacing the pixel

The first red lift is proportional to the missing red, remaining highlight
headroom, the Water correction and Red recovery controls, and highlight
protection. Its coefficient moves from `0.42` for likely material toward `0.18`
for likely water. Open-water weight also reduces excess saturation and imposes
a soft red ceiling, which is the main defense against magenta water.

```text
highlight headroom = 1 - highlight protection × (max(R, G, B) / 255)²
red addition = Water correction × Red recovery
               × mix(0.42, 0.18, water)
               × max(0, G - R) × (1 - R / 255)
               × highlight headroom
```

For the local pass, red deficit, structure, scene-wide red loss, and water
suppression become a material confidence:

```text
water suppression = 1 - water × mix(0.88, 0.28, structure)
material confidence = clamp(red deficit
                            × (0.14 + 1.72 × structure)
                            × water suppression
                            × scene red-loss factor)
```

Textured areas therefore receive more local color recovery than equally cyan,
flat areas. A Retinex-style estimate compares each channel with its broad local
average, but keeps target red/green and blue/green ratios cool in deep-blue
scenes. The result is mixed back into the current pixel with bounded weights:
chroma blending cannot exceed `0.66`, and luminance blending cannot exceed
`0.32`. It is never an unrestricted replacement.

In practice, a flat saturated cyan patch tends toward high water weight and low
structure, so it receives less red. A coral edge with the same cast has more
structure and therefore more material confidence. Bright sand can still gain a
small luma-preserving warm correction through a separate brightness term, while
very dark or nearly neutral regions receive little intervention. These are
overlapping responses, not four segmented regions.

### 5. Rebuild tone and finish the requested edit

The 1st and 99.5th luminance percentiles drive contrast stretch, ignoring most
isolated black or clipped pixels. Gamma, exposure, highlights, shadows, black
point, brightness, hue, saturation, haze reduction, and vignette then follow
the visible editor values. Local fusion restores separation and controlled haze
lift; export quality adds the final clarity and sharpening pass. Crop,
orientation, LUT, and encoding are applied by the surrounding image service.

Previews use bounded dimensions and omit the most expensive final detail pass,
so interaction stays responsive. The exported file is never an enlarged copy
of the preview.

The portable implementation lives in
[`underwater_processor.dart`](lib/core/processing/underwater_processor.dart).
iOS also provides a Core Image implementation that mirrors the same scene and
per-pixel weighting strategy with GPU-friendly sampling and Gaussian blurs. It
is intentionally not bit-identical to the portable renderer. Tests keep both
paths measurable as the algorithm evolves.

## Platform scope

| Capability | iOS | macOS | Android | Windows |
| --- | --- | --- | --- | --- |
| JPEG, PNG, and WebP correction | Yes | Yes | Yes | Yes |
| Photos-library import | Native Photos APIs | Native Photos APIs | System media access | — |
| File import and folder export | Yes | Yes | Yes | Yes |
| HEIC/HEIF decode | Native | Native | Platform dependent | Platform dependent |
| Supported RAW still decode | Core Image | Core Image | ImageDecoder on API 28+ | — |
| Standard video export | MP4/MOV via AVFoundation | MP4/MOV with local `ffmpeg` | — | — |
| Custom `.cube` LUT for stills | Yes | Yes | Yes | Yes |

AquaRecover is photo-first. Video support is currently strongest on Apple
platforms, custom LUTs are not supported by the native iOS video path, and
proprietary formats such as Blackmagic RAW, REDCODE RAW, and ProRes RAW are not
implemented.

## Privacy is part of the architecture

The repository contains no login, advertising framework, telemetry client,
upload endpoint, or cloud backend. Selected media is decoded and rendered on
the device. If an item exists only in iCloud, the operating system may download
it before providing AquaRecover with a local file.

Still exports are freshly encoded. Video exports remove metadata by default.
The iOS and macOS privacy manifests declare no tracking and no collected data.
The complete data flow is documented in the [privacy policy](PRIVACY.md) and
[on-device privacy model](docs/ON_DEVICE_PRIVACY.md).

## Try AquaRecover

The [latest GitHub release](https://github.com/FinnGrndl/AquaRecover/releases/latest)
contains the Android APK, Windows installer, and signed macOS disk image. iOS
builds are distributed through TestFlight while store preparation is in
progress.

Current source version: `1.3.2+14`.

To run from source with the same Flutter toolchain used by CI:

```bash
git clone https://github.com/FinnGrndl/AquaRecover.git
cd AquaRecover
flutter pub get
flutter run -d macos
```

Use `flutter devices` to choose another connected target. The
[development guide](docs/DEVELOPMENT.md) covers the complete setup for Flutter,
Xcode, iOS Simulator test media, physical Apple devices, Android, Windows,
release builds, the simulator harness, tests, and common permission problems.

## Build, study, or improve it

This project is useful at several levels: as an underwater editor, as a readable
color-restoration pipeline, and as a Flutter application that crosses into
PhotoKit, Core Image, AVFoundation, platform file pickers, and desktop
packaging without introducing a backend.

```text
lib/core/processing/        restoration, transforms, LUTs, image/video services
lib/core/photo/             photo-library permission and asset access
lib/core/persistence/       export paths and versioned sidecars
lib/features/editor/        editor, queue, crop, compare, and export workflow
ios/ and macos/             native Apple runners and processing bridges
android/ and windows/       desktop/mobile platform runners
platform_overrides/         native files retained during project regeneration
test/                       unit, widget, metadata, and regression tests
tool/                       evaluator, benchmark, tuner, and simulator harness
```

Start with:

- [Building and running AquaRecover](docs/DEVELOPMENT.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Contributing](CONTRIBUTING.md)
- [Release automation](docs/RELEASE_AUTOMATION.md)
- [Security policy](SECURITY.md)

Algorithm changes should include a focused test. Private reference images can
be placed in the ignored `test/img` directory for local evaluation, but must
never be committed unless you own the necessary redistribution rights.

## License

AquaRecover is available under the [MIT License](LICENSE). Dependency licenses
are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and inside the
app under **About > Licenses**.
