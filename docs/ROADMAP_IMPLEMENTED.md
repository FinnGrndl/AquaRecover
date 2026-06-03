# Roadmap implementation summary

Date: 2026-04-24

This build implements the product roadmap that was listed in the previous audited MVP README.

## Implemented product features

- Apple-style Cupertino interface with blurred glass panels, rounded controls, and responsive phone/desktop layouts.
- One-tap Auto correction plus manual controls for recovery, color, saturation, hue, brightness, sharpness, contrast, exposure, highlights, shadows, black point, clarity, haze, vignette, and JPEG quality.
- Water-type presets: Auto, Natural, Vivid reef, Deep dive, Macro, Shallow, Green water, Red filter, Artificial light, and Pro.
- Batch processing queue for full dive sets.
- Video trimming before export.
- Before/after photo scrubber and side-by-side video comparison.
- Live device-rendered still preview for fast slider feedback.
- Photos-library import and optional save-to-library flow on iOS/macOS/Android through `photo_manager`.
- Export presets for Social, Archive, and Pro edit workflows.
- Metadata privacy controls.
- Nondestructive `.aquarecover.json` sidecar next to every export.
- LUT workflows with built-in looks and `.cube` import.
- RAW still support through platform native decode bridges.
- RAW frame-stream descriptors with safe validation; processing uses the optional macOS `ffmpeg` CLI backend when available.

## On-device implementation notes

- No cloud or backend is called by the app code.
- Still images are processed in Dart using the local `image` package after local/native decode.
- HEIC/HEIF and RAW stills are decoded locally through platform bridges where supported.
- Video processing is not bundled in the current app binary. It is local on macOS when an external `ffmpeg` command-line binary is available; other platforms report video export as unavailable while keeping photo recovery enabled.
- Output is written to the app documents directory and optionally saved to Photos.

## Remaining production hardening

- Run `flutter analyze`, `flutter test`, and real device builds locally.
- Add production video pipelines, either via native AVFoundation/VideoToolbox/MediaCodec paths or a reviewed bundled FFmpeg distribution.
- Add true shader-based final export pipelines using Core Image/Metal and Android GPU APIs for better speed and battery use.
- Add a complex FFmpeg filter graph for blended custom `.cube` LUT intensity on video.
- Wire optional LibRaw FFI for wider camera RAW support.
- Review proprietary RAW video SDKs individually.
