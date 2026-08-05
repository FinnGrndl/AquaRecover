# Architecture

## Boundaries

AquaRecover separates the editor workflow from media inspection, processing,
native bridges, persistence, and photo-library access. The Flutter UI owns
selection and state transitions; services own file and platform work.

```text
Files / platform photo library
             |
             v
        MediaClassifier --------> MediaInspectionService
             |
             v
          MediaJob <------------ EditorPage / EditorWorkflow
             |
       +-----+-------------------+
       |                         |
       v                         v
ImageRestorationService   VideoRestorationService
       |                         |
       +--> Dart isolate         +--> iOS AVFoundation/Core Image
       +--> iOS Core Image       +--> macOS local ffmpeg process
       +--> platform RAW decode
             |
             v
     export + JSON sidecar + optional Photos save
```

## Editor state

`EditorPage` owns the current jobs, selected item, restoration and image
transform settings, LUT, trim values, export options, and workflow step. It
calls small services for side effects. UI components in
`lib/features/editor/widgets` receive values and callbacks.

A single import moves to the edit step. A multi-import creates ready queue
entries without writing output files. Confirming the export view starts either
the selected export or `_processQueue` for the remaining batch. An individual
export marks only its selected queue item as complete; the later full-batch
action skips completed items. Queue items move through ready, processing,
complete, or failed states. Photos saving remains an explicit export option and
uses add-only access on iOS. The selection sheet can remove ready items while a
batch is running; the item currently being processed remains locked.

Import inspection runs in bounded groups of three. File reads can overlap, but
the app avoids unbounded image decodes that would increase peak memory use. The
dimension probe reads decoder metadata instead of producing a full pixel image.

`ExportLibraryService` lists supported files inside `AquaRecover Exports`.
Deletion is restricted to that directory and also removes the adjacent
`.aquarecover.json` sidecar. The UI supports individual and confirmed batch
deletion. The imported source and copies in Photos are never touched.

## Still-image pipeline

`ImageRestorationService` validates the encoded file before decoding. On iOS,
standard stills and supported built-in LUTs use the native Core Image channel.
Other platforms and custom still LUTs use a Dart isolate:

1. Decode and validate dimensions and pixel count.
2. Collect robust global statistics.
3. Recover red loss with open-water and subject weighting.
4. Apply bounded white balance and percentile contrast stretch.
5. Apply tone, color, and vignette values.
6. Fuse the global result with a local illumination estimate.
7. Add export-only clarity/sharpening.
8. Apply the selected LUT.
9. Apply crop, quarter-turn rotation, and flip settings, then encode JPEG or
   PNG.

The limits are 16,384 pixels on either axis and 120 million decoded pixels.
Encoded still files are limited to 512 MiB before the decode step.

## Preview and export

Preview work uses bounded dimensions and skips the final high-cost detail pass.
Changes are scheduled away from the UI thread. Full-resolution export reruns the
pipeline from the original file; the preview bitmap is not upscaled or reused as
the final output. Recent preview renders are kept in a small memory cache so
switching between edited and split views does not start the same render twice.

## Apple native channels

- `aqua_recover/image`: native still preview and export on iOS.
- `aqua_recover/video`: AVFoundation/Core Image video export on iOS.
- `aqua_recover/raw`: HEIC/HEIF and supported RAW decode on Apple platforms,
  plus platform-supported decode on Android.

`RawBridge.swift` is the single RAW/image decode bridge for each Apple target.
`IosVideoProcessor.swift` registers the two iOS processing channels. The
bootstrap script copies the maintained files from `platform_overrides` and adds
them to the generated Xcode targets.

## Video

iOS standard video export runs through AVFoundation and Core Image. It supports
trim bounds, optional audio, metadata removal, built-in presets, and the current
restoration settings.

macOS can use an `ffmpeg` executable already installed on the machine. Arguments
are passed as an array rather than a shell command. No FFmpeg binary is bundled.
Android reports video export as unavailable and keeps the photo workflow active.

## Persistence

`OutputPaths` creates sanitized names in the app documents directory.
`SidecarService` writes a versioned `.aquarecover.json` document containing
settings and file names but no absolute source path. `PhotoLibraryService` can
then ask the platform to add the exported file to Photos. When no local copy is
requested, rendering and preview use temporary storage; no output or sidecar
appears in the local export directory.
`FolderExportService` copies output to a directory selected by the system file
picker and creates a numbered file name instead of overwriting an existing
file. Batch items reuse the selected folder for the current editor session.

## Dependencies

The processing core uses the Dart `image` package and Apple system frameworks.
There is no database, network client, backend, analytics SDK, or account layer.
The optional `native/libraw_bridge` directory is a scaffold only and is not
linked into release builds.
