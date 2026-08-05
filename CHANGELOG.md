# Changelog

Changes are grouped by release. AquaRecover follows semantic versioning for
source releases; the number after `+` is the mobile build number.

## Unreleased

### Changed

- Presets now open first, keep their identity through manual adjustments, and
  include an adjustable strength plus a neutral None option.
- Adjustment bubbles reset their individual value to the active preset base;
  the global reset action was removed.
- The preview button now switches between edited and split views. Holding the
  edited preview temporarily reveals the original.
- Reworked the import and export surfaces with a more compact native layout,
  dark export glass, and a bounded split review preview.
- Added visible explanations and accessibility hints for every image
  adjustment.
- The preview toggle no longer changes the active editing tool.
- Simplified adjustment controls with full-width sliders and a single visible
  value in the adjustment browser.
- Added a nondestructive Crop tab with aspect ratios, pinch positioning,
  90-degree rotation, horizontal and vertical flip, native iOS export, and
  sidecar persistence.
- Reduced editor panel height, removed duplicate panel headings, and updated
  the tools to a lighter gray glass treatment.

### Fixed

- Collapsed editor tools can be reopened through the visible up-arrow control.
- Split comparison previews no longer render underneath the editor tools.
- Split mode reuses rendered previews and keeps the same blurred immersive
  background as the normal edited view.

## 0.4.0 - 2026-08-05

### Added

- Native iOS Photos picker for single and multiple selection.
- Automatic processing after a multi-image import.
- Editor adjustment browser showing every current image value.
- Add-only Photos permission for saving automatic iOS exports.
- iOS privacy manifest, Files sharing, and opening-in-place support.
- Repeatable iOS Simulator import harness.
- New iOS app icon set.
- One canonical app icon source with generated Android, iOS, and macOS sets.
- Local reference media is ignored and no longer part of the tracked source.

### Changed

- Reworked the editor around a compact, dark Cupertino photo workflow.
- Tuned deep-blue restoration to preserve a believable underwater separation
  while recovering attenuated warm colors.
- Reduced the default contrast stretch and made it scene-aware.
- Updated the application identifiers to `io.github.finngrndl.aquarecover`.
- Removed local Apple development-team selection from the shared Xcode project.

### Fixed

- Photos saving after multi-selection no longer asks for full-library access on
  iOS.
- Native Apple project resources now include the privacy manifest in release
  builds on iOS and macOS.

Earlier development milestones are available in the Git history.
