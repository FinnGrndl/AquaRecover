# Code and security review

Last updated: 2026-08-05 for 0.4.0.

## Controls in place

- Input paths must exist and point to files before processing.
- Encoded still size, decoded dimensions, and pixel count are bounded.
- RAW frame descriptors validate dimensions, frame rate, and pixel format.
- Export file names are sanitized and length-limited.
- Temporary native decode files use the operating-system temporary directory
  and are removed on a best-effort basis.
- FFmpeg receives an argument list, uses `-nostdin`, and has redacted/truncated
  user-facing logs.
- Metadata removal is enabled by default.
- Sidecars omit absolute source paths.
- iOS automatic exports use add-only Photos permission.
- Native decode and image work are moved off the platform/UI thread.
- No network endpoint, analytics SDK, authentication secret, or bundled FFmpeg
  runtime is present.

## Release checks completed locally

- Dart formatting and static analysis.
- Flutter unit and widget tests.
- Processor reference-pair evaluation and performance benchmark.
- iOS Simulator launch, native Photos picker, single-image editor, and automatic
  three-image processing with Photos saves.
- Unsigned iOS device release build with the privacy manifest in the app bundle.
- Privacy plist parsing and source scans for example identifiers, TODO markers,
  network clients, and obvious secret names.

Run the commands again on the release commit; results from a working tree are
not a substitute for CI on the tagged source.

## Remaining risks

### Media decoders

Image and video parsing handles untrusted input. Package and operating-system
decoders need regular updates. Fuzzing is not currently part of this repository.

### Resource use

Still dimensions are bounded, but long videos can consume substantial CPU,
battery, temporary storage, and time. A storage preflight and reliable native
progress/cancellation remain open work.

### Platform coverage

The current release has no recorded physical-iPhone or Android-device test.
Limited Photos access, low-storage behavior, large HEIC/RAW files, and store
archives still need device validation.

### Optional codecs

No FFmpeg library is bundled. If that changes, codec licenses, patents, binary
linkage, privacy manifests, export controls, and store rules require a fresh
review. Proprietary RAW video SDKs need their own contracts and threat review.

### Removed test assets

Private processor fixtures are excluded from current source by `.gitignore`.
They still exist in older commits, so the repository history must be rewritten
before it becomes public. A normal deletion commit is not sufficient because
the old blobs remain retrievable.

## Reporting

Follow [SECURITY.md](../SECURITY.md). Reports that could expose media, paths, or
device resources should not be filed as public issues.
