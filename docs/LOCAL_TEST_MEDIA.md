# Local test media

The image-quality evaluator, tuner, and benchmark can use private fixtures from
`test/img`. That directory is ignored by Git and is not part of the open-source
distribution.

Expected optional files:

- `before1.webp`, `after1.webp`, and further numbered before/after pairs for
  local reference comparison.
- JPEG files for visual evaluation and performance measurements.
- `SportDiver_20260427_063800.MOV` for the optional video-frame comparison.

Keep the files only on machines where their storage and use are permitted. Do
not copy fixtures into a public issue, pull request, CI artifact, screenshot, or
release archive. A fresh checkout works without this directory: the private
reference-pair test is reported as skipped, while synthetic processor tests
remain mandatory.

Run the local tools after restoring the private directory:

```bash
dart run tool/evaluate_samples.dart
dart run tool/benchmark_processor.dart
dart run tool/tune_references.dart
```

The first two commands return exit code 2 with a clear message when the local
directory is absent. The tuner also stops without changing source when no
complete before/after pair is available.
