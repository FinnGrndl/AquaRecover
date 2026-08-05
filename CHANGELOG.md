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
- Added a thumbnail overview for imported media with individual queue removal,
  including removal of ready items before batch export.
- Added the canonical app icon to the import screen branding.
- Replaced the separate import card and navigation title with one full-screen
  branded start surface.
- Expanded the mobile export settings surface to fill the area directly below
  the top bar.
- Multi-selection now creates a ready batch without writing output files;
  processing and saving begin only after export confirmation.
- Added local export library and detail pages with preview and deletion of the
  exported file and its sidecar.
- Added multi-selection, select-all, batch deletion, and delete-all actions to
  the local export library.
- Export destinations can now be local-only, Photos-only, or both. Photos-only
  exports keep no durable copy or sidecar in AquaRecover.
- Added Files as an independent export destination. A system folder picker is
  used once and the same folder receives every item in a batch.
- Added a separate export action for the currently selected batch item. The
  full batch action skips items that were already exported individually.
- Replaced the editor export label with a neutral gray review checkmark.
- Parallelized import metadata inspection in bounded groups and avoided full
  pixel decoding when only image dimensions are required.

### Fixed

- Collapsed editor tools can be reopened through the visible up-arrow control.
- Split comparison previews no longer render underneath the editor tools.
- Split mode reuses rendered previews and keeps the same blurred immersive
  background as the normal edited view.
- The export background now extends through the top safe area while its controls
  remain positioned below the status bar.
- The editor background now extends behind the status bar and Dynamic Island.
- Completed exports now show the saved photo directly without a comparison
  slider.

## 0.4.0 - 2026-08-05

### Added

- Native iOS Photos picker for single and multiple selection.
- Automatic batch setup after a multi-image import.
- Editor adjustment browser showing every current image value.
- Add-only Photos permission for saving iOS exports.
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
