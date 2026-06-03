# Bug and security audit

Date: 2026-04-24

## Bugs found and fixed

1. **Mobile layout crash**
   - Problem: `_buildControlsPane()` returned a `ListView` that was nested inside another vertical `ListView` on narrow/mobile layouts.
   - Risk: Flutter runtime error: vertical viewport with unbounded height.
   - Fix: Controls now render as a scrollable `ListView` only in the desktop/wide side panel and as a non-scrollable `Column` in the outer mobile list.

2. **HEIC/HEIF imports were classified as photos but sent to Dart image decoding**
   - Problem: The Dart `image` package does not list HEIC/HEIF as supported formats.
   - Risk: iPhone HEIC photos would fail with `Could not decode image bytes`.
   - Fix: HEIC/HEIF now route through the native platform decode bridge before restoration.

3. **Unbounded raw video parameters**
   - Problem: RAW frame width, height, frame rate, and pixel format were user-entered with only positive-number checks.
   - Risk: accidental or malicious resource exhaustion in FFmpeg.
   - Fix: Added safe bounds, pixel-format allow-listing, and validation in both the dialog and processing service.

4. **Output filename safety**
   - Problem: Export filenames used the input basename directly.
   - Risk: odd/control characters and extremely long names could create fragile output paths.
   - Fix: Output stems and extensions are sanitized and length-limited.

5. **Video audio copy fragility**
   - Problem: `-c:a copy` could fail when source audio was not MP4-compatible.
   - Risk: valid MOV/other files failing during export.
   - Fix: Export now transcodes optional audio to AAC and adds `+faststart` for easier playback/share.

6. **Native decode blocking**
   - Problem: iOS/macOS/Android method-channel decode work ran synchronously on the platform thread.
   - Risk: UI freezes on large images/RAW files.
   - Fix: Native decode work runs on a background thread/queue and posts results back to the main thread.

## Security hardening added

- Input file existence checks before image/video processing.
- Encoded still-image byte-size cap before Dart decode.
- Decoded still-image dimension and pixel-count limits.
- Native platform decode dimension and pixel-count limits.
- RAW frame stream validation before FFmpeg input construction.
- FFmpeg is invoked with argument arrays, not shell strings.
- FFmpeg includes `-nostdin` so it cannot wait on unexpected input.
- FFmpeg logs are redacted/truncated before being shown in UI errors.
- Video exports remove metadata by default with `-map_metadata -1`.
- Optional LibRaw C bridge now checks decoded dimensions and row-stride overflow.


## Additional implementation audit in on-device full build

- Fixed another narrow-layout risk: the preview pane no longer returns an unconstrained inner vertical `ListView` on phone layouts.
- Fixed invalid Dart escaping in `.cube` LUT path escaping.
- Photos-library limited access is now accepted through `PermissionState.hasAccess` instead of requiring full access only.
- Photos limited-access management reloads albums after the user changes the selection.
- Added macOS Photos usage strings and the macOS Photos Library entitlement to the bootstrap/platform override files.
- Added Android `READ_MEDIA_VISUAL_USER_SELECTED` for modern limited media access flows.
- Added nondestructive sidecar output that stores edit settings without storing full original file paths.
- Added cancel control for FFmpeg video jobs.
- Added manual tone controls and water-type presets with bounded values.

## Remaining risks before production

- Current local validation has run `flutter analyze`, `flutter test`, macOS build/launch, and iOS Simulator build/launch. Physical iPhone and Android builds remain unverified.
- FFmpeg/GPL licensing must be reviewed before closed-source/commercial distribution if a bundled video backend is reintroduced.
- Image/video/RAW decoders should be kept updated because media parsers are a common vulnerability surface.
- The current app uses a file picker. A production iOS app should use PhotosPicker or the iOS Photos framework with least-privilege permissions.
- Proprietary RAW video support requires vendor SDK/licensing review.
- Very large videos can still consume substantial CPU, battery, and storage. Add progress/cancel controls and storage preflight checks before production.

## Second implementation audit in full on-device build

Date: 2026-04-24

### Bugs found and fixed

1. **Duplicate native RawBridge definitions on Apple platforms**
   - Problem: iOS `AppDelegate.swift` and macOS `MainFlutterWindow.swift` embedded a `RawBridge` class while separate `RawBridge.swift` files were also copied during bootstrap.
   - Risk: Xcode compile failure due to duplicate type definitions.
   - Fix: Entry-point files now only register the bridge; each Apple platform has exactly one `RawBridge.swift`.

2. **RAW/HEIC intermediate PNGs were written to the user-visible export folder and left behind**
   - Problem: platform-decoded intermediates used the normal export directory.
   - Risk: extra storage use and possible privacy leakage from temporary decode files.
   - Fix: intermediates now go to the OS temporary directory and are deleted after restoration with best-effort cleanup.

3. **Photos album switching/import could get stuck after an exception**
   - Problem: album load and selected-asset resolution had no local error recovery.
   - Risk: Photos modal could remain loading/importing indefinitely.
   - Fix: added catch paths that reset loading/importing state and show a friendly error.

4. **Trim text parsing produced raw parser errors**
   - Problem: invalid start/end text relied on `double.parse` exceptions.
   - Risk: unfriendly errors and weaker validation.
   - Fix: uses `double.tryParse`, friendly messages, and a 24-hour trim bound.

5. **RAW video dialog exposed only four supported pixel formats**
   - Problem: the model allowed seven safe pixel formats, but the UI only showed the first four.
   - Risk: supported raw streams such as `rgb24`, `rgba`, and `gray16le` could not be selected from the dialog.
   - Fix: replaced the segmented control with wrapped format chips for every allow-listed format.

6. **Bootstrap script could insert duplicate native permissions/Info.plist keys if edited or partially rerun**
   - Problem: insertions were regex-only and not key-aware.
   - Risk: messy platform files or duplicate keys after partial reruns.
   - Fix: bootstrap now uses idempotent Python insertion checks for Android permissions and Apple Photos usage keys.

### Checks run in this environment

- `bash -n scripts/bootstrap_flutter_project.sh`
- Plist/privacy manifest/entitlement parsing with Python `plistlib`
- Source scan confirming exactly one `RawBridge` definition per Apple platform override
- Basic Dart delimiter-balance scan across `lib/`
- Source scans for stale Material imports, network/analytics/backend references, TODO/FIXME markers, and duplicate bridge definitions

### Still requiring local validation

- `flutter analyze`
- `flutter test`
- `./scripts/bootstrap_flutter_project.sh` on a Mac with Flutter installed
- Xcode build/run on macOS and a physical iPhone
- Real-media tests with HEIC, JPEG, DNG, MOV/MP4, and at least one `.cube` LUT
