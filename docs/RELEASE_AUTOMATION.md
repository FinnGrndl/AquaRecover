# Release automation

AquaRecover separates continuous checks from distributable builds.

- Pull requests and `main` run formatting, analysis, tests, and debug builds.
- Pushes to `main` use git-cliff to calculate the next semantic version,
  synchronize the Flutter build number and visible version strings, regenerate
  `CHANGELOG.md`, and commit the result when a version changed.
- Only a verified `git cherry-pick -x` on `release/**` can start release builds.
  The workflow rejects direct commits, merge commits, cherry-picks from outside
  `main`, and release trees that differ from the source commit.

## Version rules

Commit subjects follow Conventional Commits:

- `fix:` increments the patch version.
- `feat:` increments the minor version.
- a `!` or `BREAKING CHANGE:` increments the major version.
- `chore:`, `ci:`, `docs:`, `build:`, `style:`, and `test:` do not increment the
  version.

`pubspec.yaml` is the build source of truth. `tool/sync_version.dart` updates it,
the in-app version constants, the issue template, README, and dependency notice
together. Flutter passes the same version and build number to Android, Apple,
and Windows builds.

The version workflow needs repository `contents: write` permission. If `main`
is protected, allow the GitHub Actions bot to write the generated
`chore(release): prepare vX.Y.Z` commit or replace the direct push with a
required version pull request.

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

## Prepare a release branch

First wait for the `main` CI and version workflow to finish. Use the exact
tested `main` commit as the source. The release branch starts at its parent so
the source commit can be replayed with the required provenance marker:

```bash
git fetch origin main --tags
git switch main
git pull --ff-only

SOURCE_SHA="$(git rev-parse HEAD)"
VERSION="$(awk '$1 == "version:" { split($2, value, "+"); print value[1] }' pubspec.yaml)"

git switch -c "release/$VERSION" "${SOURCE_SHA}^"
git cherry-pick -x "$SOURCE_SHA"
git push -u origin "release/$VERSION"
```

That push creates four release outputs:

- signed Android APK;
- Windows Inno Setup installer (`.exe`);
- macOS disk image (`.dmg`), optionally signed and notarized;
- signed iOS IPA, validated and uploaded to TestFlight.

The desktop and Android packages remain available as GitHub Actions artifacts
for 30 days. The IPA is retained for 14 days. No private test media is included.

The TestFlight job starts only after the other three platform packages have
finished successfully. Apple may need additional processing time before the
uploaded build appears in App Store Connect.

## Tagging

After every platform job and the TestFlight upload succeeds, the workflow
creates the annotated `vX.Y.Z` tag automatically. The tag points to the original
tested commit on `main`, whose tree is identical to the cherry-picked release
commit. A conflicting existing tag fails the workflow instead of moving it.

The workflow does not publish a GitHub Release. Review the three downloadable
packages, then create a release from the generated tag and attach the retained
artifacts if permanent public downloads are wanted.

## Local checks

```bash
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
flutter build apk --release --no-pub
flutter build ios --release --no-codesign --no-pub
flutter build macos --release --no-pub
```

Windows and signed TestFlight outputs are built on their matching GitHub-hosted
runners. git-cliff, Inno Setup, Flutter, and the packaging commands used by the
workflow are free software or operating-system tools. TestFlight distribution
still requires an Apple Developer Program membership.
