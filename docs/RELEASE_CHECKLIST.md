# Release checklist

Use this list on the exact commit that will be tagged. Do not mark a store item
complete from a Simulator build.

## Source and licensing

- [x] Root MIT license added.
- [x] Contribution, conduct, support, and security policies added.
- [x] Direct dependency licenses reviewed and documented.
- [x] In-app dependency license view available.
- [x] One licensed canonical icon generates every platform icon set.
- [x] Private `test/img` files removed from current Git tracking and ignored.
- [ ] Old `test/img` blobs removed by a reviewed history rewrite before the
      repository becomes public.
- [x] Tracked media assets reviewed; no third-party screenshots, fonts, or LUT
      files are included, and the canonical icon is covered by the root license.
- [ ] `git status --short` is clean on the release commit.

## Automated checks

```bash
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
git diff --check
```

- [x] Checks pass in the local release workspace.
- [x] Optional local evaluator and benchmark pass with private fixtures present.
- [ ] GitHub `Format, analyze, test, and Android build` job passes.
- [ ] GitHub `Apple debug builds` job passes.
- [ ] Both CI jobs are required by `master` branch protection.

## Repository settings

- [ ] Repository visibility is public.
- [ ] Description, website/support URL, and topics are set.
- [ ] Issues and private vulnerability reporting are enabled.
- [ ] Default branch protection requires pull requests and CI.
- [ ] A release tag is signed or otherwise tied to the reviewed commit.

## iOS and App Store

- [x] Non-example bundle identifier is present in source.
- [x] `PrivacyInfo.xcprivacy` is part of the iOS and macOS app resources.
- [x] Unsigned iOS release build succeeds locally.
- [ ] Final bundle identifier is registered to the publisher.
- [ ] Distribution team and signing selected.
- [ ] Physical iPhone smoke test passes.
- [ ] Photos picker, add-only save, denial, limited access, and iCloud download
      paths pass on a physical device.
- [ ] App Store archive validation passes.
- [ ] Store description, screenshots, icon, support URL, published `PRIVACY.md`
      URL, age rating,
      and privacy answers are complete.

## Android and Play Store

- [x] Non-example application ID is present in source.
- [ ] Private upload key and release signing configured outside Git.
- [ ] Debug and release builds pass with an installed Android SDK.
- [ ] Smoke tests pass on supported Android API levels.
- [ ] AAB validation, store listing, content rating, and Data safety form complete.

## Tagging the source release

1. Update `CHANGELOG.md` and the version in `pubspec.yaml`.
2. Run every automated check above.
3. Review `git diff` and commit the release.
4. Wait for required CI jobs on that commit.
5. Create the tag and GitHub release from the same commit:

```bash
git tag -s v0.4.0 -m "AquaRecover 0.4.0"
git push origin master v0.4.0
```

If signed tags are not configured, use an annotated tag and record the reviewed
commit SHA in the GitHub release notes.
