# 0.4.0 release scope

This file records what is present in the first open-source release candidate.
It is not a promise that every path is production-ready on every platform.

## Included

- Single-photo import into a compact Cupertino editor.
- Native iOS Photos selection.
- Automatic processing when several images are selected.
- Before/original/split preview modes.
- Nine underwater-oriented looks and nineteen image adjustments.
- JPEG and PNG exports with nondestructive JSON sidecars.
- Optional Photos saving, using add-only access on iOS automatic exports.
- Native iOS HEIC/RAW decode where supported.
- Native iOS still and standard-video processing.
- Portable Dart still processing for macOS, Android, tests, and fallback cases.
- Optional local macOS FFmpeg path for video and raw frame streams.
- Built-in LUTs and custom `.cube` LUTs for still images.
- Input-size, output-path, metadata, and permission hardening.

## Deliberately not included

- Accounts, subscriptions, analytics, advertising, or cloud processing.
- A bundled FFmpeg runtime.
- Android video export.
- Custom `.cube` LUT video export on iOS.
- Proprietary RAW video formats.
- Store signing material or automated store deployment.

## Release status

The 0.4.0 code has passed local simulator and build checks. Physical-device
coverage, test-image rights, CI on the public commit, and store-owner setup are
tracked in [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md).
