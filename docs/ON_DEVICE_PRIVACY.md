# On-device privacy model

## Data flow

1. The user selects media from Files or the platform photo library.
2. The operating system gives AquaRecover a file or a temporary local asset.
3. The app inspects and decodes it locally.
4. Processing runs in Dart, Apple Core Image/AVFoundation, Android
   ImageDecoder, or an optional local macOS `ffmpeg` process.
5. The export is written to the app documents directory.
6. If requested, the operating system adds that export to Photos.

No app code sends the media or its settings to a server.

## Photo-library permissions

iPhone import uses the native system picker and does not require broad read
access to the library. iPad uses AquaRecover's PhotoKit browser and therefore
requests Photos read access while respecting the system's limited-library
selection. Saving an export requests add-only access. macOS and Android use
their platform media access flows and should be tested against the current
limited-library behavior before each store release.

The iOS media-picker dependency also contains optional camera and foreground
location APIs. AquaRecover declares the corresponding purpose strings so iOS
can explain those capabilities if the system requests access. The app does not
track location, request background location, or open the camera without a user
action.

If an original exists only in iCloud Photos, Apple's Photos service may download
it before the app receives a local representation. That transfer belongs to the
operating system's photo-library flow, not an AquaRecover endpoint.

## Network behavior

The application has no account, analytics, advertising, crash-reporting,
upload, or cloud-processing client. Dependencies may contain platform support
for targets that AquaRecover does not ship; the release application does not
call those network paths.

## Encryption and export compliance

AquaRecover does not implement proprietary, non-standard, or other non-exempt
encryption. The iOS app declares `ITSAppUsesNonExemptEncryption` as `false` so
App Store Connect can apply the corresponding export-compliance exemption
without asking the same question for every uploaded build. Any future feature
or dependency that adds cryptography or encrypted communications requires this
classification to be reviewed before release.

## Exports and metadata

- Dart still exports are encoded from decoded pixels and do not copy normal
  source EXIF/GPS blocks.
- Native Apple and video paths honor the metadata-strip export option; stripping
  is enabled by default.
- A JSON sidecar records edit settings, source/output names, LUT and trim data.
  It does not record the original absolute path.
- Files remain in the app documents directory until the user removes them or the
  application container is deleted.

## Manifests and declarations

The iOS and macOS `PrivacyInfo.xcprivacy` files declare no tracking, collected
data, tracking domains, or required-reason API categories in app-owned code.
This declaration must be reviewed again whenever a package or native API is
added. App Store and Play Console privacy answers must match the final archived
binary, not only this document.

## Test media

Real-camera fixtures can contain personal metadata and visible people or
locations. `test/img` is therefore ignored and remains local. It must not be
uploaded as a CI artifact or attached to an issue or pull request.
