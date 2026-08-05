# Contributing

Bug reports, focused fixes, tests, and documentation improvements are welcome.
For large UI changes or a new processing backend, open an issue first so the
scope can be agreed before implementation.

## Development setup

Use Flutter 3.44.1 or a compatible stable release with Dart 3.12 or newer.
Apple builds also require Xcode; Android builds require the Android SDK.

```bash
flutter pub get
flutter analyze
flutter test
```

Run the format check before opening a pull request:

```bash
dart format --output=none --set-exit-if-changed lib test tool
```

## Processing changes

Changes to the restoration algorithm should include a focused unit test. When
you have suitable local media, run the optional evaluator and benchmark as well:

```bash
dart run tool/evaluate_samples.dart
dart run tool/benchmark_processor.dart
```

Private reference files stay in the ignored `test/img` directory and must not be
attached to a pull request. See `docs/LOCAL_TEST_MEDIA.md`.

## Test media

Only add media that you created or have permission to publish. Remove GPS,
camera-owner, and other personal metadata before committing it. Private local
fixtures are never part of the repository.

## Pull requests

- Keep a pull request limited to one problem.
- Add tests for behavior changes where practical.
- Update the README, changelog, or architecture notes when behavior changes.
- Do not commit signing certificates, provisioning profiles, local SDK paths,
  generated build output, or personal media.
- Confirm that analysis, tests, and relevant platform builds pass.

By contributing code, you agree that it may be distributed under the MIT
License in this repository.
