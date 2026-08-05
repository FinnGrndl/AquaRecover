# Next steps

## Before the 0.4.0 source release

- Rewrite the Git history to remove every old `test/img` blob, then verify the
  rewritten repository before making it public.
- Run CI from the public GitHub repository and require both jobs on `master`.
- Enable GitHub private vulnerability reporting.
- Review the final diff and tag the exact commit that passed CI.

## Before an App Store submission

- Register `io.github.finngrndl.aquarecover` in the Apple Developer account or
  choose the final permanent identifier before creating the archive.
- Select the distribution team and create an App Store archive.
- Test on a physical iPhone with local and iCloud-backed HEIC/JPEG media,
  limited Photos access, denied permission, low storage, and interrupted export.
- Prepare screenshots, description, support URL, privacy URL, age rating, and
  App Store privacy answers.
- Confirm the icon and all permission text in the archived build.

## Before a Play Store submission

- Replace debug release signing with a private upload key and document key
  recovery outside this repository.
- Build and test an AAB on current Android versions and different memory tiers.
- Verify system picker and limited-library behavior.
- Complete the Data safety form from the final AAB.

## Engineering work after the first release

- Split editor state and long build sections into smaller controllers/widgets
  without changing the established import and adjustment workflow.
- Add golden tests for the compact and wide editor layouts.
- Add physical-device performance baselines and storage preflight checks.
- Bring the portable and native renderers under a shared set of numeric fixture
  expectations.
- Replace the optional macOS FFmpeg process with a reviewed native video path if
  video becomes part of the primary product scope.
- Wire LibRaw only if its supported formats justify the packaging and maintenance
  cost.
