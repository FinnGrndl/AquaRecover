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
       +--> Dart isolate         +--> iOS/macOS AVFoundation/Core Image
       +--> iOS/macOS Core Image +--> Android Media3 + baked 3D LUT
       +--> platform RAW decode  +--> Windows ffmpeg lut3d + baked 3D LUT
             |
             v
     export + JSON sidecar + optional Photos save
```

## Editor state

`EditorPage` owns the current jobs, selected item, per-job `MediaEditState`
values, trim values, export options, and workflow step. The active restoration,
transform, and LUT fields mirror the selected job so existing preview widgets
remain simple. Switching jobs stores the old values and restores the target
values. UI components in `lib/features/editor/widgets` receive values and
callbacks, while small services handle side effects.

A single import moves to the edit step. A multi-import creates ready queue
entries without writing output files. Confirming the export view starts either
the selected export or `_processQueue` for the remaining batch. Successful
items are removed from the in-memory queue immediately. Failed or cancelled
items remain available, while processing items stay locked. `_processQueue`
iterates over stable job IDs so removing successful entries cannot shift an
index and skip later media. Photos saving remains an explicit export option and
uses add-only access on iOS.

Import inspection runs in bounded groups of three. File reads can overlap, but
the app avoids unbounded image decodes that would increase peak memory use. The
dimension probe reads decoder metadata instead of producing a full pixel image.

The batch copy picker writes the selected job's immutable `MediaEditState` to
explicit target job IDs. Applying to all requires a confirmation dialog. Export
loads the matching state before each queued item is rendered, so copied and
individually tuned values are preserved across a batch.

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
9. Apply quarter-turn rotation and flips, straighten into a filled safe canvas,
   apply the normalized crop, then encode JPEG or PNG.

The limits are 16,384 pixels on either axis and 120 million decoded pixels.
Encoded still files are limited to 512 MiB before the decode step.

## Preview and export

Preview work uses bounded dimensions and skips the final high-cost detail pass.
Previews render on one long-lived worker isolate (`PreviewRenderWorker`). It
keeps the last three decoded and downscaled sources, so a slider change only
re-runs the restoration on the preview bitmap instead of decoding the original
again. A queued render for a file is replaced when a newer one for the same
file arrives, so fast slider drags cannot build a backlog. Full-resolution
export reruns the pipeline from the original file; the preview bitmap is not
upscaled or reused as the final output. Recent preview renders are kept in a
small memory cache so switching between edited and split views does not start
the same render twice.

The portable renderer works directly on a packed 8-bit RGBA buffer. Images in
other formats (16-bit PNG/TIFF, palette, grayscale) are converted first so the
algorithm always sees 0–255 values. Per-image constants live in sendable
correction and fusion plans; exports above about 1.5 MP are split into row
bands that run on up to eight worker isolates and produce the same pixels as
the sequential path. `pow` calls with a per-image exponent use interpolated
lookup tables. Settings, LUT and export options share one JSON format
(`toJson`/`fromJson` on the models) across isolates, sidecars and tools.

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

iOS and macOS standard video export runs through AVFoundation and Core Image.
Both runners compile the same `AquaMediaPipeline.swift`, which holds the
restoration kernels, scene statistics, LUTs, and export code and imports neither
Flutter nor UIKit/AppKit. `IosVideoProcessor.swift` and `MacMediaProcessor.swift`
only register the `aqua_recover/video` and `aqua_recover/image` channels around
it. The pipeline supports trim bounds, optional audio, metadata removal, MP4 or
MOV containers, built-in presets, custom `.cube` LUTs (parsed once and cached),
cancellation, and the current restoration settings. The editor keeps a per-item
representative frame position and uses it in both the editor and export review;
the position does not trim or otherwise change the exported timeline. Local
video exports open with the app's video player.

On iOS 26 and later, the native bridge submits a user-initiated
`BGContinuedProcessingTask` and reports `AVAssetExportSession` progress. iOS
15–25 use a finite `UIApplication` background task as a fallback. Neither path
adds a permanent audio, location, or network background mode.

macOS previously launched a locally installed `ffmpeg`, which the App Sandbox
blocks. It now uses the shared native pipeline and keeps the `ffmpeg` process
only for RAW video descriptors in unsandboxed development builds. Arguments are
passed as an array rather than a shell command. No FFmpeg binary is bundled.
Stills and previews on macOS also use Core Image, which adds HEIC and RAW
decoding without a Dart fallback.

Android and Windows have no AquaRecover shaders, so `VideoLutBaker` turns the
restoration into a 33³ colour table first. It samples five frames from the
trimmed range, stacks them into one scene sample for the statistics, and runs
`UnderwaterProcessor.bakeColorLattice`, the same per-pixel correction the still
renderer uses, over every lattice colour. Each colour fills a 2×2 block so the
local-structure term sees a flat region. A creative LUT is composed on top.
Android hands the table to Media3 Transformer as a `SingleColorLut`, tone-mapping
HDR clips to SDR first; Windows writes a `.cube` file next to an `ffmpeg`
`lut3d` filter. The table cannot hold Retinex fusion, sharpening, or the
vignette, so those stay Apple and stills only. Cancelling bumps a generation
counter that stops jobs still sampling or baking, then cancels the running
Transformer or kills the `ffmpeg` process.

## Timelines

`lib/core/timeline` turns photos and clips into one short movie. A
`TimelineProject` holds the aspect (16:9, 9:16, 1:1), quality, frame rate, and
an ordered list of `TimelineClip`s. Each clip has its own grade
(`RestorationSettings`), look (`LutProfile`), in and out points or still
duration, a cut or crossfade from the previous clip, and an optional slow zoom
for photos. `TimelineLayout` is the single source of timing: a crossfade
overlaps two clips by the project's transition length, clamped to half of
either clip. The renderers receive the layout instead of re-deriving it.
Projects are saved as versioned JSON by `TimelineProjectStore` and only
reference media by path.

`TimelineRenderService` picks a backend:

| Platform | Renderer | Grade per clip |
| --- | --- | --- |
| iOS, macOS | `AquaTimelineRenderer.swift`: AVAssetReader → Core Image → AVAssetWriter, audio mixed with `AVAudioMix` ramps | Full `AquaMediaPipeline` filters per frame; photos graded once and cached |
| Android | `TimelineExportBridge.kt`: one Media3 sequence with `Presentation`, slow-zoom `MatrixTransformation`, and forced audio | Baked `SingleColorLut`; crossfades render as a short dip to black because Media3 sequences cannot overlap items |
| Windows (and tooling) | `FfmpegTimelineRenderer`: one filter graph with `lut3d`, `zoompan`, `xfade`, and `acrossfade` | Baked `.cube` per clip |

The editor lives in `lib/features/timeline`. `TimelineController` owns the
immutable project, the selection, the playhead, a bounded undo and redo history,
and a debounced autosave. `TimelineEditorPage` stacks the viewer, the transport,
the centred-playhead `TimelineStrip`, and the Cut, Color, and Deliver panels; on
screens 900 points and wider the panels move into a side column. The viewer uses
the accurate still renderer for photos and the platform player with a
colour-matrix approximation for video, so scrubbing stays real time while the
render applies the full grade.

`TimelineGradeBaker` caches baked tables by source range, grade, and look, so a
second export after a small edit only re-bakes the clips that changed.

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
