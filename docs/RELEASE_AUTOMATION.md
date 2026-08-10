# Release automation

AquaRecover separates continuous checks from distributable builds.

- Pull requests run formatting, analysis, tests, and debug builds directly.
- Pushes to `main` use git-cliff to calculate the next semantic version,
  synchronize the Flutter build number and visible version strings, regenerate
  `CHANGELOG.md`, and commit the result when synchronized files changed. The version
  workflow then dispatches exactly one CI run for that commit SHA. This avoids
  testing the pre-version commit and repeating the same tests in two workflows.
- Each major release line has one persistent branch, such as `release/1`.
  Each release adds one snapshot commit containing the complete difference from
  the previous release to the tested `main` tree. The workflow rejects commits
  without a `Release-Source` trailer, stale main sources, release trees that
  differ from the source commit, reused version tags, and source commits without
  a successful dispatched CI run.

## Version rules

Commit subjects follow Conventional Commits:

- `fix:` increments the patch version.
- `feat:` increments the minor version.
- a `!` or `BREAKING CHANGE:` increments the major version.
- `chore:`, `ci:`, `docs:`, `build:`, `style:`, and `test:` do not increment the
  version.

The first public release baseline is `v1.1.0`, configured as git-cliff's
`initial_tag`. Once that tag exists, subsequent versions are calculated from the
latest matching release tag using the rules above.

`pubspec.yaml` is the build source of truth. `tool/sync_version.dart` updates it,
the in-app version constants, the issue template, README, and dependency notice
together. Flutter passes the same version and build number to Android, Apple,
and Windows builds.

The version workflow needs repository `contents: write` and `actions: write`
permissions. If `main` is protected, allow the GitHub Actions bot to write the
generated `chore(release): prepare vX.Y.Z` commit or replace the direct push
with a required version pull request.

## Required secrets

Store binary values as one-line base64 strings. Do not commit certificates,
profiles, private keys, passwords, or decoded files.

Android release signing requires repository secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

The `testflight` GitHub environment requires:

- `APPLE_TEAM_ID`
- `IOS_DISTRIBUTION_CERTIFICATE_BASE64`
- `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`
- `IOS_PROVISIONING_PROFILE_BASE64`

Add the App Store Connect API credentials as repository secrets so the iOS
upload and optional macOS notarization can both use them:

- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY_BASE64`

The provisioning profile must be an App Store profile for
`io.github.finngrndl.aquarecover`. App Store Connect must already contain the
matching iOS app record. The API key needs permission to upload builds.

macOS Developer ID signing is optional. Add these repository secrets to produce
a signed DMG:

- `MACOS_DEVELOPER_ID_CERTIFICATE_BASE64`
- `MACOS_DEVELOPER_ID_CERTIFICATE_PASSWORD`

When the App Store Connect API secrets are also available as repository
secrets, the signed DMG is submitted to Apple's notary service and stapled.
Without the Developer ID certificate the workflow still creates an unsigned
DMG and records that fact in the workflow summary.

## Update a release line

First wait for the `main` CI and version workflow to finish. Use the exact
tested `main` commit as the source. A major-version branch is created only once
from the latest published baseline in that line. For example, to create the 1.x
line after `v1.1.0`:

```bash
git fetch origin main --tags
git switch -c release/1 v1.1.0
git show origin/main:scripts/update_release_line.sh | bash -s -- origin/main
git push -u origin release/1
```

For every later 1.x release, update the same branch in a clean worktree:

```bash
git fetch origin main --tags
git switch release/1
git pull --ff-only
git show origin/main:scripts/update_release_line.sh | bash -s -- origin/main
git push origin release/1
```

Reading the helper from `origin/main` ensures that pipeline-only changes can
update the release tooling without first modifying `release/1`. The helper
finds the previous source marker, stages the complete tree difference, and
creates exactly one commit named `chore(release): snapshot vX.Y.Z` with a
`Release-Source` trailer. It then verifies that the snapshot tree exactly
matches the tested source.

If the version in `main` already has a tag pointing to a different commit, the
helper stops before changing `release/1`. This prevents CI-only work from
silently rebuilding an already published version. Do not push the release
branch until the helper has completed successfully.

That push builds four release outputs in parallel:

- signed Android APK;
- Windows Inno Setup installer (`.exe`);
- macOS disk image (`.dmg`), optionally signed and notarized;
- signed iOS IPA, validated and uploaded to TestFlight.

The workflow can also be retried manually from GitHub Actions. Select the exact
`release/<major>` branch, such as `release/1`, when dispatching it. The same
snapshot, version, tag, and successful-CI checks run before any release build
starts, so the manual entry point cannot bypass the release gate.

All four workflow artifacts are retained for 90 days, the maximum available to
this public repository. The APK, Windows installer, and DMG are also attached
to the GitHub Release as permanent public downloads. The signed IPA remains
private and is distributed through TestFlight. No private test media is
included.

The signed IPA is created alongside the other platform packages. Its TestFlight
upload starts only after Android, Windows, macOS, and iOS builds have all
finished successfully. This keeps the expensive builds parallel without
publishing a partial release. Apple may need additional processing time before
the uploaded build appears in App Store Connect.

The iOS archive and TestFlight upload run on GitHub's `macos-26` image. The
workflow verifies the selected iPhoneOS SDK before installing dependencies or
signing so an outdated runner fails early instead of producing an unusable IPA.

## Tagging

After every platform job and the TestFlight upload succeeds, the workflow
creates the annotated `vX.Y.Z` tag automatically. The tag points to the original
tested commit on `main`, whose tree is identical to the release snapshot
commit. A conflicting existing tag fails the workflow instead of moving it.

The same final job creates a GitHub Release, explicitly marks it as the latest
release, generates its notes, and attaches the APK, Windows installer, and DMG
as permanent public downloads. The signed IPA remains a private 90-day workflow
artifact and is distributed through TestFlight rather than attached publicly.

All external GitHub Actions are pinned to immutable commit SHAs. Dependabot
tracks their release tags and proposes updates without allowing a mutable tag to
change code inside a signing job unexpectedly.

## Local checks

```bash
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
flutter build apk --release --no-pub
flutter build ios --release --no-codesign --no-pub
flutter build macos --release --no-pub
```

Android, Windows, macOS, and signed iOS outputs are built on their matching
GitHub-hosted runners. git-cliff, Inno Setup, Flutter, and the packaging commands
used by the workflow are free software or operating-system tools. TestFlight
distribution still requires an Apple Developer Program membership.
