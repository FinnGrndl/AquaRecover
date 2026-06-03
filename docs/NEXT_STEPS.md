# Production next steps

Most of the prior product roadmap is now implemented in source. The remaining work is production hardening, native performance, licensing, and device validation.

## Required local validation

- Run `flutter analyze`.
- Run `flutter test`.
- Run a macOS debug build.
- Run an iPhone debug build on a physical device.
- Run Android debug builds on Android 12, 13, 14, and 15 devices/emulators.
- Test Photos limited-library access on iOS and Android 14+.
- Test macOS Photos permission and sandbox behavior.

## Media test matrix

- Photos: JPEG, PNG, WebP, TIFF, HEIC, HEIF.
- RAW stills: DNG first, then CR2/CR3/NEF/ARW/RAF/RW2 after LibRaw wiring.
- Videos: MOV, MP4/H.264, MP4/H.265, M4V, MKV, files with no audio, files with AAC, files with PCM/other audio.
- Raw frame streams: yuv420p, nv12, rgb24, rgba.
- Edge cases: very large images, long videos, low storage, iCloud-backed Photos assets, cancelled video jobs.

## Performance upgrades

- Replace final still-image CPU loops with Core Image/Metal on iOS/macOS and AGSL/RenderEffect/Vulkan/OpenGL on Android.
- Add accurate video progress for the chosen production backend.
- Add storage-space preflight checks before video export.
- Cache preview-sized frames separately from full-resolution export.
- Add background task handling for long video exports where platform policy allows it.

## RAW and pro video

- Wire the optional LibRaw C bridge into Dart FFI for broader camera RAW support.
- Add CinemaDNG folder/sequence import.
- Evaluate vendor SDKs for Blackmagic RAW, REDCODE RAW, and ProRes RAW.
- Add Apple Log to Rec.709 and HDR/SDR transform options.
- Add timecode-aware export naming for pro workflows.

## Distribution

- Review FFmpeg, x264/x265, patent, GPL/LGPL, and App Store/Play Store requirements before shipping any bundled video backend.
- Prefer AVFoundation/VideoToolbox and Android MediaCodec pipelines for production video export if your distribution model requires avoiding bundled GPL codecs.
- Add App Store privacy labels based on the final shipped build.
- Confirm `PrivacyInfo.xcprivacy` is included in the Xcode app target resources before archive.
