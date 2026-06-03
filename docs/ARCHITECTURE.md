# Architecture

## Design approach

AquaRecover uses Flutter's Cupertino widget set for a native-feeling Apple-style interface across iOS and macOS, while still supporting Android. Custom blurred `GlassPanel` surfaces provide a lightweight Liquid-Glass-inspired hierarchy for controls and preview panels.

## On-device processing

The app has no backend processing path. Media flows through local Files/Photos APIs, local decoders, local restoration services, and local export writers.

```text
Files / Photos import
        |
        +--> Dart image decode for JPEG/PNG/WebP/TIFF
        +--> Native Core Image/ImageDecoder bridge for HEIC/HEIF/RAW stills
        +--> Optional macOS ffmpeg CLI for video and raw frame streams
        |
        v
RestorationSettings + optional LUT + optional trim
        |
        v
Local export file + .aquarecover.json sidecar
        |
        +--> Optional Photos-library save
```

## Still-image pipeline

The still-image pipeline is deterministic and runs locally:

1. Sample the image to estimate channel means and low/high percentiles.
2. Compensate red-channel attenuation using green as a local reference.
3. Apply bounded gray-world white balance.
4. Stretch RGB channels between robust percentiles.
5. Apply gamma, contrast, exposure, brightness, shadow/highlight, black-point, hue, saturation, vibrance, haze, vignette, and clarity controls.
6. Apply optional built-in or `.cube` LUT.
7. Encode JPEG or PNG locally.

## Video pipeline

Videos are not bundled with an FFmpeg runtime in the current Flutter build. On macOS, video and raw frame streams can be processed locally when a command-line `ffmpeg` binary is installed. The generated filter chain uses color balance, tone/saturation/gamma, optional hue rotation, unsharp masking, optional vignette, optional LUT filters, and MP4-compatible output formatting. Optional trim arguments are placed around the input/output to avoid processing unwanted portions where possible. On iOS, Android, and iOS Simulator, the UI leaves photo recovery available and reports video export as unavailable.

For production performance, replace the FFmpeg-based color path with native GPU pipelines:

- iOS/macOS: Core Image/Metal + AVFoundation/VideoToolbox.
- Android: MediaCodec + AGSL/RenderEffect/OpenGL/Vulkan.

## RAW still pipeline

RAW photos are rendered to an intermediate sRGB PNG through the native bridge, then passed through the same restoration pipeline as normal stills.

- iOS/macOS: Core Image platform decode and `CIRAWFilter` where available.
- Android: `ImageDecoder` on Android 9/API 28+ for platform-supported RAW/DNG.
- `native/libraw_bridge` contains an optional LibRaw C ABI scaffold for broader camera RAW support.

## RAW video pipeline

For raw frame streams, the app asks for dimensions, frame rate, and pixel format, validates those values, and passes them to FFmpeg as rawvideo input arguments. For CinemaDNG or other image sequences, add a directory picker and invoke FFmpeg with an image-sequence pattern such as `frame_%05d.dng`.

## Nondestructive sidecars

Each export writes a `.aquarecover.json` sidecar containing schema version, creation time, input/output names, restoration settings, export options, LUT selection, trim settings, and RAW frame descriptor when relevant. The sidecar intentionally stores file names rather than full original paths.
