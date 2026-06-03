# On-device privacy model

AquaRecover is designed as a local-first app.

## Data flow

1. The user imports local media from Files or Photos.
2. The app receives a local file path or an OS-provided local asset file.
3. Images are decoded locally in Dart or by native platform image frameworks.
4. Videos are processed locally only on macOS when an external `ffmpeg` command-line binary is available.
5. Restored exports are written to the app documents directory.
6. If enabled, the app asks the OS to save the export back to Photos.

## What the app does not do

- No account login.
- No cloud processing endpoint.
- No analytics endpoint.
- No media upload from app code.
- No network permission is intentionally added for the implemented workflow.

## Operating-system caveat

When using Photos with iCloud Photos enabled, iOS/macOS may download an original asset before the app receives a local file. That transfer is handled by Apple's Photos/iCloud system services, not by AquaRecover's app code.

## Metadata

- Video exports strip metadata by default.
- Still-image exports are encoded fresh from decoded pixels, so common EXIF/GPS metadata is not copied by the Dart encoder path.
- Archive export preset intentionally preserves the user's metadata-toggle choice.
- Every export writes a `.aquarecover.json` sidecar with restoration settings. The sidecar stores input/output file names, not full original file paths.

## Security controls

- Input files must exist before processing starts.
- Output filenames are sanitized.
- Encoded still images have a byte-size cap.
- Decoded image dimensions and pixel counts are limited.
- RAW video descriptors validate width, height, frame rate, and pixel format before invoking FFmpeg.
- FFmpeg is invoked with an argument array, not a shell command string.
- FFmpeg uses `-nostdin`.
- UI-facing FFmpeg logs are redacted and truncated.
- macOS app sandbox entitlements are limited to user-selected read/write files and Photos-library access for the implemented workflow.
