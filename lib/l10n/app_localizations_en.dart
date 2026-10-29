// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'AquaRecover';

  @override
  String get cancel => 'Cancel';

  @override
  String get ok => 'OK';

  @override
  String get done => 'Done';

  @override
  String get apply => 'Apply';

  @override
  String get edit => 'Edit';

  @override
  String get delete => 'Delete';

  @override
  String get share => 'Share';

  @override
  String get undo => 'Undo';

  @override
  String get redo => 'Redo';

  @override
  String get change => 'Change';

  @override
  String get manage => 'Manage';

  @override
  String get optional => 'Optional';

  @override
  String get preview => 'Preview';

  @override
  String get original => 'Original';

  @override
  String get selected => 'Selected';

  @override
  String get status => 'Status';

  @override
  String get libraryBack => 'Library';

  @override
  String get exportAction => 'Export';

  @override
  String get exportTitle => 'Export';

  @override
  String get exportAll => 'Export all';

  @override
  String get exportingEllipsis => 'Exporting...';

  @override
  String get exportingShort => 'Exporting';

  @override
  String get licenses => 'Licenses';

  @override
  String get movies => 'Movies';

  @override
  String get diveLogbook => 'Dive logbook';

  @override
  String get localExports => 'Local exports';

  @override
  String get aboutApp => 'About AquaRecover';

  @override
  String get quickTour => 'Quick Tour';

  @override
  String aboutBody(String version) {
    return 'Version $version\\n\\nOn-device underwater color recovery for photos, RAW stills, videos, LUTs, and local exports.';
  }

  @override
  String get destinationPhotos => 'Photos';

  @override
  String get destinationFiles => 'Files';

  @override
  String get presetNone => 'None';

  @override
  String get presetAuto => 'Auto';

  @override
  String get presetNatural => 'Natural';

  @override
  String get presetVivid => 'Vivid reef';

  @override
  String get presetDeep => 'Deep dive';

  @override
  String get presetMacro => 'Macro';

  @override
  String get presetShallow => 'Shallow';

  @override
  String get presetGreenWater => 'Green water';

  @override
  String get presetRedFilter => 'Red filter';

  @override
  String get presetArtificialLight => 'Artificial light';

  @override
  String get presetNoneHelp => 'Leaves the image unchanged.';

  @override
  String get presetAutoHelp =>
      'Balanced one-tap correction for common blue-green water.';

  @override
  String get presetNaturalHelp =>
      'Lower contrast and saturation for a documentary look.';

  @override
  String get presetVividHelp => 'Extra contrast and color for reef scenes.';

  @override
  String get presetDeepHelp => 'Stronger red recovery for deeper dives.';

  @override
  String get presetMacroHelp => 'More local detail for close subjects.';

  @override
  String get presetShallowHelp =>
      'Gentle correction for snorkeling and sunlit shallow water.';

  @override
  String get presetGreenWaterHelp =>
      'Counters green plankton-rich water without overdoing magenta.';

  @override
  String get presetRedFilterHelp =>
      'Compensates footage shot with a red dive filter.';

  @override
  String get presetArtificialLightHelp =>
      'Protects highlights from torches and strobes.';

  @override
  String get mediaKindPhoto => 'Photo';

  @override
  String get mediaKindRawPhoto => 'RAW photo';

  @override
  String get mediaKindVideo => 'Video';

  @override
  String get mediaKindRawVideo => 'RAW video';

  @override
  String get jobStatusReady => 'Ready';

  @override
  String get jobStatusProcessing => 'Processing';

  @override
  String get jobStatusComplete => 'Complete';

  @override
  String get jobStatusFailed => 'Failed';

  @override
  String get beforeAfterSideBySide => 'Side by side';

  @override
  String get beforeAfterSplit => 'Split';

  @override
  String get exportPresetSocial => 'Social';

  @override
  String get exportPresetArchive => 'Archive';

  @override
  String get exportPresetProEdit => 'Pro edit';

  @override
  String get lutNone => 'None';

  @override
  String get lutCoralWarm => 'Coral Warm';

  @override
  String get lutBlueWater => 'Blue Water';

  @override
  String get lutGreenWater => 'Green Water';

  @override
  String get lutCustomCube => 'Custom .cube';

  @override
  String get cropOriginal => 'Original';

  @override
  String get cropFree => 'Free';

  @override
  String get cropSquare => 'Square';

  @override
  String get workflowImport => 'Import';

  @override
  String get workflowEdit => 'Edit';

  @override
  String get workflowExport => 'Export';

  @override
  String get toolPresets => 'Presets';

  @override
  String get toolAdjust => 'Adjust';

  @override
  String get toolCrop => 'Crop';

  @override
  String get toolColor => 'Color';

  @override
  String get toolDetails => 'Details';

  @override
  String get toolLut => 'LUT';

  @override
  String get toolVideo => 'Video';

  @override
  String get toolPresetsSubtitle => 'Starting profile and strength';

  @override
  String get toolAdjustSubtitle => 'All image adjustments';

  @override
  String get toolCropSubtitle => 'Crop, rotate, and flip';

  @override
  String get toolColorSubtitle => 'Water cast and color balance';

  @override
  String get toolDetailsSubtitle => 'Haze, clarity, and sharpening';

  @override
  String get toolLutSubtitle => 'Look-up table and vignette';

  @override
  String get toolVideoSubtitle => 'Preview frame and trim';

  @override
  String get adjRecovery => 'Water correction';

  @override
  String get adjRecoveryHelp =>
      'Controls the underwater cast-recovery stage only. It strengthens color recovery and local neutralization, but does not scale exposure, contrast, saturation, or sharpening.';

  @override
  String get adjContrastStretch => 'Contrast stretch';

  @override
  String get adjContrastStretchHelp =>
      'Expands the measured dark-to-bright range. High values can make murky scenes punchier but may clip detail.';

  @override
  String get adjContrast => 'Contrast';

  @override
  String get adjContrastHelp =>
      'Changes separation around the midtones without re-running the underwater color recovery.';

  @override
  String get adjGamma => 'Gamma';

  @override
  String get adjGammaHelp =>
      'Moves midtone brightness while keeping the black and white endpoints mostly fixed.';

  @override
  String get adjBrightness => 'Brightness';

  @override
  String get adjBrightnessHelp =>
      'Adds or removes a uniform amount of light after the main correction.';

  @override
  String get adjExposure => 'Exposure';

  @override
  String get adjExposureHelp =>
      'Multiplies scene brightness like a small exposure adjustment. It affects shadows and highlights together.';

  @override
  String get adjHighlights => 'Highlights';

  @override
  String get adjHighlightsHelp =>
      'Brightens or darkens the lightest parts while protecting the rest of the tonal range.';

  @override
  String get adjShadows => 'Shadows';

  @override
  String get adjShadowsHelp =>
      'Opens or deepens darker areas without applying a full-image brightness change.';

  @override
  String get adjBlackPoint => 'Black point';

  @override
  String get adjBlackPointHelp =>
      'Deepens the darkest tones. Increase carefully to avoid losing shadow detail.';

  @override
  String get adjTemperature => 'Temperature';

  @override
  String get adjTemperatureHelp =>
      'Final warm-cool trim after the water correction. The white balance picker sets it from a tap.';

  @override
  String get adjTint => 'Tint';

  @override
  String get adjTintHelp =>
      'Final green-magenta trim. Positive values remove a leftover green cast.';

  @override
  String get adjRedRecovery => 'Red recovery';

  @override
  String get adjRedRecoveryHelp =>
      'Targets warm colors absorbed by water. Its result is multiplied by Water correction, so both controls work together.';

  @override
  String get adjAutoWhiteBalance => 'Auto white balance';

  @override
  String get adjAutoWhiteBalanceHelp =>
      'Balances the average red, green, and blue levels within safe bounds. Lower it when intentional lighting should stay warm or cool.';

  @override
  String get adjSaturation => 'Saturation';

  @override
  String get adjSaturationHelp =>
      'Changes the intensity of all colors equally. High values can exaggerate color noise and water tint.';

  @override
  String get adjVibrance => 'Vibrance';

  @override
  String get adjVibranceHelp =>
      'Boosts muted colors more than colors that are already strong.';

  @override
  String get adjHue => 'Hue';

  @override
  String get adjHueHelp =>
      'Small hue rotations help match strobes, filters, and water type.';

  @override
  String get adjHighlightProtection => 'Highlight protection';

  @override
  String get adjHighlightProtectionHelp =>
      'Reduces correction in the brightest areas to preserve strobes, the sun, and reflective equipment.';

  @override
  String get adjHazeReduction => 'Haze reduction';

  @override
  String get adjHazeReductionHelp =>
      'Reduces blue-green veil and increases separation in low-contrast water.';

  @override
  String get adjClarity => 'Clarity';

  @override
  String get adjClarityHelp =>
      'Adds local midtone contrast to reveal texture. It is gentler than sharpening edges directly.';

  @override
  String get adjSharpness => 'Sharpness';

  @override
  String get adjSharpnessHelp =>
      'Strengthens fine edges during export. Too much can emphasize noise or compression artifacts.';

  @override
  String get adjVignette => 'Vignette';

  @override
  String get adjVignetteHelp =>
      'Darkens the image edges to guide attention toward the center.';

  @override
  String get compareEdited => 'Edited';

  @override
  String get compareOriginal => 'Original';

  @override
  String get compareSplit => 'Split';

  @override
  String get previewFitLabel => 'Fit';

  @override
  String get previewFillLabel => 'Fill';

  @override
  String get previewFillAction => 'Fill preview area';

  @override
  String get previewFitAction => 'Fit entire image';

  @override
  String get startTagline => 'Private, on-device restoration';

  @override
  String get importHeroTitle => 'Restore underwater color';

  @override
  String get importHeroTitleQueue => 'Add or open media';

  @override
  String get importHeroBody =>
      'Choose one photo or video to edit. Select several to prepare one batch, then export everything with one confirmation.';

  @override
  String get importHeroBodyQueue =>
      'Add more items to the queue or continue with the selected image.';

  @override
  String get chooseFromPhotos => 'Choose from Photos';

  @override
  String get importFiles => 'Import Files';

  @override
  String makeMovie(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Make a movie from $count items',
      one: 'Make a movie',
    );
    return '$_temp0';
  }

  @override
  String get editSelected => 'Edit selected';

  @override
  String get showEditedPreview => 'Show edited preview';

  @override
  String get showSplitPreview => 'Show split preview';

  @override
  String previewFitHint(String action) {
    return '$action. Pinch with two fingers to inspect details; double-tap to reset zoom.';
  }

  @override
  String get reviewExport => 'Review export';

  @override
  String get previousItem => 'Previous item';

  @override
  String get nextItem => 'Next item';

  @override
  String selectionPosition(int current, int total) {
    return 'Selection $current/$total';
  }

  @override
  String itemPosition(int current, int total, String name) {
    return '$current of $total - $name';
  }

  @override
  String queueReadyCount(int count) {
    return '$count ready';
  }

  @override
  String queueProcessingCount(int count) {
    return '$count processing';
  }

  @override
  String queueFailedCount(int count) {
    return '$count failed';
  }

  @override
  String get copyEditsTooltip => 'Copy this photo’s edits';

  @override
  String copiedEdits(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Copied edits to $count photos.',
      one: 'Copied edits to 1 photo.',
    );
    return '$_temp0';
  }

  @override
  String get applyEditsToAllTitle => 'Apply edits to all photos?';

  @override
  String get applyEditsToAllBody =>
      'This photo’s edits will be applied to all other photos in the queue.';

  @override
  String get whiteBalance => 'White balance';

  @override
  String get manualAdjustments => 'Manual adjustments';

  @override
  String get videoExportUnavailable => 'Video export unavailable';

  @override
  String get backToEdit => 'Back to edit';

  @override
  String get noMediaSelected => 'No media selected';

  @override
  String get noMediaSelectedBody => 'Choose a local photo or video to begin.';

  @override
  String get goToImport => 'Go to import';

  @override
  String get importedVideo => 'Imported video';

  @override
  String get importedPhoto => 'Imported photo';

  @override
  String lutNamed(String name) {
    return 'LUT $name';
  }

  @override
  String get retrySelected => 'Retry selected';

  @override
  String get exportingSelected => 'Exporting selected...';

  @override
  String get exportedStatus => 'Exported';

  @override
  String get exportSelected => 'Export selected';

  @override
  String get batchExport => 'Batch export';

  @override
  String get selectedItem => 'Selected item';

  @override
  String get noItemSelected => 'No item selected';

  @override
  String get videoFrameHelp =>
      'Choose the frame used in the editor and export preview. This does not change the exported video timeline.';

  @override
  String get previewFrame => 'Preview frame';

  @override
  String get framePreviewUnavailable =>
      'Frame preview is not available for this video on this device.';

  @override
  String get preparingVideoTimeline => 'Preparing video timeline…';

  @override
  String get trimVideo => 'Trim video';

  @override
  String get startSeconds => 'Start seconds';

  @override
  String get endSeconds => 'End seconds';

  @override
  String rawVideoSummary(int width, int height, String fps, String format) {
    return 'RAW video: ${width}x$height ${fps}fps $format';
  }

  @override
  String get importCubeLut => 'Import .cube LUT';

  @override
  String get lutIntensity => 'LUT intensity';

  @override
  String get exportSettings => 'Export settings';

  @override
  String get exportSettingsSubtitle => 'Format, quality, and destination';

  @override
  String get keepInApp => 'Keep in AquaRecover';

  @override
  String get addToPhotos => 'Add to Photos';

  @override
  String get exportToFiles => 'Export to Files';

  @override
  String get destinationsHelpWithPhotos =>
      'Choose one or more destinations. Photos and Files exports do not appear under Local Exports unless a local copy is enabled.';

  @override
  String get destinationsHelp =>
      'Choose one or more destinations. Files exports do not appear under Local Exports unless a local copy is enabled.';

  @override
  String get jpegQuality => 'JPEG quality';

  @override
  String get stripMetadata => 'Strip metadata';

  @override
  String get keepVideoAudio => 'Keep video audio';

  @override
  String get beforeAfterImage => 'Before/After image';

  @override
  String get beforeAfterImageHelp =>
      'Export each photo as one image showing the original and the restored version';

  @override
  String get beforeAfterSplitHelp =>
      'Split: original on the left half, restored on the right';

  @override
  String get beforeAfterSideBySideHelp =>
      'Side by side: landscape photos are stacked, portrait photos sit next to each other';

  @override
  String get beforeAfterLabels => 'Before and After labels';

  @override
  String get beforeAfterLabelsHelp =>
      'Show small Before and After labels on the image';

  @override
  String get beforeLabel => 'Before';

  @override
  String get afterLabel => 'After';

  @override
  String get queue => 'Queue';

  @override
  String itemsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items selected',
      one: '1 item selected',
    );
    return '$_temp0';
  }

  @override
  String get noMediaImported => 'No media imported.';

  @override
  String editItem(String name) {
    return 'Edit $name';
  }

  @override
  String get removeFromQueue => 'Remove from queue';

  @override
  String removeItemFromQueue(String name) {
    return 'Remove $name from queue';
  }

  @override
  String get workingLocally => 'Working locally';

  @override
  String get idle => 'Idle';

  @override
  String get exportContinuesInBackground =>
      'The export can continue if you switch apps. Return to AquaRecover to check its progress.';

  @override
  String get statusReady => 'Ready.';

  @override
  String get statusNoFileSelected => 'No file selected.';

  @override
  String get statusNoPhotosImported => 'No local Photos items were imported.';

  @override
  String photosImportFailedStatus(String error) {
    return 'Photos import failed: $error';
  }

  @override
  String get photosImportFailed => 'Photos import failed';

  @override
  String get itemsSkippedTitle => 'Some items were skipped';

  @override
  String itemsSkippedBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected items could not be copied from Photos.',
      one: '1 selected item could not be copied from Photos.',
    );
    return '$_temp0 Items stored only in iCloud must be downloaded in Photos first.';
  }

  @override
  String get waitingForPhotos => 'Waiting for your Photos selection...';

  @override
  String loadedLut(String name) {
    return 'Loaded LUT $name.';
  }

  @override
  String get inspectingMedia => 'Inspecting imported media...';

  @override
  String inspectingMediaProgress(int done, int total) {
    return 'Inspecting imported media... $done/$total';
  }

  @override
  String get noSupportedMedia => 'No supported readable media files found.';

  @override
  String importedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Imported $count items',
      one: 'Imported 1 item',
    );
    return '$_temp0';
  }

  @override
  String importedSkipped(int count) {
    return ', skipped $count unsupported';
  }

  @override
  String get importNothingSaved => 'Nothing is saved until you confirm export.';

  @override
  String get preparingExport => 'Preparing export...';

  @override
  String failedStatus(String message) {
    return 'Failed: $message';
  }

  @override
  String get exportFailed => 'Export failed';

  @override
  String get exportCompleteEmpty => 'Export complete. The queue is empty.';

  @override
  String exportCompleteRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Export complete. $count items remaining.',
      one: 'Export complete. 1 item remaining.',
    );
    return '$_temp0';
  }

  @override
  String get exportingAllMedia => 'Exporting all selected media...';

  @override
  String get queueCancelled => 'Queue cancelled.';

  @override
  String batchFinished(int count) {
    return 'Batch export finished: $count exported and removed';
  }

  @override
  String batchFinishedFailed(int count) {
    return ', $count failed';
  }

  @override
  String exportingItem(String name) {
    return 'Exporting $name on this device...';
  }

  @override
  String get chooseFilesFolderFirst =>
      'Choose a Files export folder before exporting.';

  @override
  String exportedTo(String file, String destinations) {
    return 'Exported $file to $destinations.';
  }

  @override
  String get trimStartNotNumber => 'Trim start must be a number of seconds.';

  @override
  String get trimEndNotNumber => 'Trim end must be a number of seconds.';

  @override
  String get trimStartNegative => 'Trim start must be zero or greater.';

  @override
  String get trimStartTooLate => 'Trim start must be less than 24 hours.';

  @override
  String get trimEndBeforeStart => 'Trim end must be after trim start.';

  @override
  String get trimEndTooLate => 'Trim end must be less than 24 hours.';

  @override
  String removedFromQueue(String name) {
    return 'Removed $name from the queue.';
  }

  @override
  String get cannotCancelExport =>
      'This export cannot be cancelled safely. It will finish shortly.';

  @override
  String get cancelRequested => 'Cancel requested.';

  @override
  String get chooseExportFolder => 'Choose export folder';

  @override
  String get exportFolderUnavailable =>
      'The selected export folder is unavailable.';

  @override
  String get folderUnavailable => 'Folder unavailable';

  @override
  String folderUnavailableBody(String error) {
    return 'AquaRecover could not use the selected folder. $error';
  }

  @override
  String shareExportedTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Share all $count exported files',
      one: 'Share the exported file',
    );
    return '$_temp0';
  }

  @override
  String shareExportsButton(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Share all $count',
      one: 'Share',
    );
    return '$_temp0';
  }

  @override
  String get videoUnavailableBuild =>
      'Video export is not available in this build. Photo recovery remains available.';

  @override
  String get videoUnavailableIos =>
      'Native iOS video export is missing from this build. Rebuild the iOS runner or run the bootstrap script, then try again.';

  @override
  String get videoUnavailableMacos =>
      'Native macOS video export is missing from this build. Rebuild the macOS runner or run the bootstrap script, then try again.';

  @override
  String get videoRawNeedsFfmpeg =>
      'RAW video export needs an ffmpeg command-line binary, which a sandboxed macOS app cannot launch. Standard MP4 and MOV clips export natively.';

  @override
  String get videoWindowsNeedsFfmpeg =>
      'Video export on Windows needs ffmpeg. Install it (for example with \"winget install ffmpeg\"), restart AquaRecover, and try again. Photo recovery remains available.';

  @override
  String get photosPermissionDenied => 'Photos permission was not granted.';

  @override
  String get timelineEmptyError =>
      'Add at least one photo or clip to the timeline.';

  @override
  String get tapValueToAdjust => 'Tap a value to adjust it';

  @override
  String get reset => 'Reset';

  @override
  String resetItem(String name) {
    return 'Reset $name';
  }

  @override
  String get openSourceLicenses => 'Open-source licenses';

  @override
  String get licensesLoadFailed => 'The license list could not be loaded.';

  @override
  String licensesIntro(String version) {
    return 'AquaRecover $version includes the following software. Select a component to read its license text.';
  }

  @override
  String get noOtherPhotosInBatch => 'There are no other photos in this batch.';

  @override
  String get copyEdits => 'Copy edits';

  @override
  String get copyEditsSubtitle =>
      'Choose the photos that should use these values.';

  @override
  String get copyFrom => 'Copy from';

  @override
  String selectItem(String name) {
    return 'Select $name';
  }

  @override
  String deselectItem(String name) {
    return 'Deselect $name';
  }

  @override
  String get applyToAll => 'Apply to all';

  @override
  String applyToCount(int count) {
    return 'Apply to $count';
  }

  @override
  String get freeformRatio => 'Freeform ratio';

  @override
  String get rotateLeft => 'Rotate left';

  @override
  String get rotateRight => 'Rotate right';

  @override
  String get flipHorizontally => 'Flip horizontally';

  @override
  String get flipVertically => 'Flip vertically';

  @override
  String get resetCrop => 'Reset crop';

  @override
  String get straighten => 'Straighten';

  @override
  String openToolsNamed(String tool) {
    return 'Open $tool tools';
  }

  @override
  String collapseToolsNamed(String tool) {
    return 'Collapse $tool tools';
  }

  @override
  String openTool(String tool) {
    return 'Open $tool';
  }

  @override
  String toolsNamed(String tool) {
    return '$tool tools';
  }

  @override
  String collapseItem(String name) {
    return 'Collapse $name';
  }

  @override
  String get editingTools => 'Editing tools';

  @override
  String get framePreview => 'Frame preview';

  @override
  String get representativeFrame => 'Representative frame';

  @override
  String get framePreviewUnavailableFormat =>
      'Frame preview unavailable for this format';

  @override
  String get previewGeneratedDuringExport => 'Preview generated during export';

  @override
  String compareModeFrame(String mode) {
    return '$mode frame';
  }

  @override
  String get exportedPhotoPreviewUnavailable =>
      'Exported photo preview unavailable.';

  @override
  String get renameHint => 'Rename';

  @override
  String get previewUnavailableFormat => 'Preview unavailable for this format.';

  @override
  String get cropArea => 'Crop area';

  @override
  String get cropAreaHint =>
      'Drag an edge or corner to crop. Drag inside to move the crop and pinch to resize it.';

  @override
  String get moveCropLeft => 'Move crop left';

  @override
  String get moveCropRight => 'Move crop right';

  @override
  String get moveCropUp => 'Move crop up';

  @override
  String get moveCropDown => 'Move crop down';

  @override
  String get photoUnreadable => 'This photo could not be read.';

  @override
  String get whiteBalanceSubtitle => 'Tap something white or grey';

  @override
  String whiteBalanceValues(String temperature, String tint) {
    return 'Temperature $temperature  ·  Tint $tint';
  }

  @override
  String get whiteBalanceTip =>
      'Sand, a slate, or a tank work well. Drag to compare spots.';

  @override
  String get photosTitle => 'Photos';

  @override
  String importCount(int count) {
    return 'Import $count';
  }

  @override
  String get openSystemSettings => 'Open System Settings';

  @override
  String get tryAgain => 'Try again';

  @override
  String get noPhotosOrVideos => 'No photos or videos found.';

  @override
  String get noneDownloadedFromPhotos =>
      'None of the selected Photos items could be downloaded. Open them in Photos first, then try again.';

  @override
  String itemsNotDownloaded(int count, int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected items could not be downloaded from Photos.',
      one: '1 selected item could not be downloaded from Photos.',
    );
    String _temp1 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: 'The remaining $remaining will be imported.',
      one: 'The remaining 1 will be imported.',
    );
    return '$_temp0 $_temp1';
  }

  @override
  String get continueAction => 'Continue';

  @override
  String get photosAccessDenied =>
      'Photos access is turned off. Allow AquaRecover to access your photo library in System Settings, then try again.';

  @override
  String get photosAccessRestricted =>
      'Photos access is restricted by the system or device settings.';

  @override
  String get photosAccessNotDetermined =>
      'Photos access has not been granted yet. Try again to show the system permission request.';

  @override
  String get photosAccessAvailable => 'Photos access is available.';

  @override
  String get photosItemNotLocal =>
      'The selected Photos item is not available locally. Open it in Photos to download the original from iCloud, then import it again.';

  @override
  String get photosItemUnreadable =>
      'The selected Photos item could not be read from local storage. Choose another item or download the original first.';

  @override
  String get photosPickerFailed => 'The Photos picker failed.';

  @override
  String get presetStrength => 'Preset strength';

  @override
  String get presetStrengthNoneHelp =>
      'None leaves the image unchanged. Choose another preset to adjust its strength.';

  @override
  String get presetStrengthHelp =>
      'Scales the selected preset while keeping later manual adjustments.';

  @override
  String presetSummary(String preset, String help) {
    return '$preset: $help';
  }

  @override
  String get waterBlue => 'Blue water';

  @override
  String get waterGreen => 'Green water';

  @override
  String get waterNeutral => 'Little color cast';

  @override
  String suggestionSemantics(String water, String preset, int strength) {
    return '$water. Suggested $preset at $strength percent.';
  }

  @override
  String suggestionTitle(String water, String preset, int strength) {
    return '$water: $preset $strength%';
  }

  @override
  String get applied => 'Applied';

  @override
  String presetChipSemantics(String preset) {
    return '$preset preset';
  }

  @override
  String presetChipSuggestedSemantics(String preset) {
    return '$preset preset, suggested';
  }

  @override
  String get reasonArtificialLight =>
      'Colors are close to neutral and highlights clip, which is typical for strobe or video-light shots.';

  @override
  String get reasonRedFilter =>
      'Red is mostly present but slightly low, as with a red dive filter.';

  @override
  String get reasonNatural =>
      'Little red is missing, so only a gentle correction.';

  @override
  String reasonGreenWater(String ratio) {
    return 'Green dominates blue (blue/green $ratio), typical for plankton-rich or lake water.';
  }

  @override
  String get reasonDeep =>
      'Almost no red remains and the scene is dark, which points to depth.';

  @override
  String get reasonShallow =>
      'Bright, moderately blue scene, typical for shallow water.';

  @override
  String get reasonAuto =>
      'Typical blue water cast; the balanced default fits.';

  @override
  String get queueLocked =>
      'Queue changes are locked until the current export finishes.';

  @override
  String get noSelectedMedia => 'No selected media.';

  @override
  String get selection => 'Selection';

  @override
  String itemsInQueue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items in the queue',
      one: '1 item in the queue',
    );
    return '$_temp0';
  }

  @override
  String itemWithStatus(String name, String status) {
    return '$name, $status';
  }

  @override
  String get rawVideoSettings => 'RAW video settings';

  @override
  String get width => 'Width';

  @override
  String get height => 'Height';

  @override
  String get frameRate => 'Frame rate';

  @override
  String get rawVideoNumbersRequired =>
      'Enter whole numbers for width and height and a number for the frame rate.';

  @override
  String get rawVideoTooSmall => 'RAW video dimensions are too small.';

  @override
  String rawVideoTooLarge(int max) {
    return 'RAW video dimensions must be at most ${max}x$max.';
  }

  @override
  String rawVideoTooManyPixels(int max) {
    return 'RAW video frames are too large. Maximum is $max pixels per frame.';
  }

  @override
  String rawVideoFrameRateRange(String min, String max) {
    return 'Frame rate must be between $min and $max fps.';
  }

  @override
  String get renderingPreview => 'Rendering preview';

  @override
  String get previewUnavailable => 'Preview unavailable';

  @override
  String get videoFramePreviewUnavailable => 'Video frame preview unavailable.';

  @override
  String get videoPreviewUnavailable => 'Video preview unavailable.';

  @override
  String get play => 'Play';

  @override
  String get pause => 'Pause';

  @override
  String metersValue(String value) {
    return '$value m';
  }

  @override
  String celsiusValue(String value) {
    return '$value °C';
  }

  @override
  String minutesValue(int count) {
    return '$count min';
  }

  @override
  String get logbook => 'Logbook';

  @override
  String get back => 'Back';

  @override
  String get importAndExport => 'Import and export';

  @override
  String get addDive => 'Add dive';

  @override
  String get dives => 'Dives';

  @override
  String get map => 'Map';

  @override
  String get noDivesYet => 'No dives yet';

  @override
  String get noDivesYetBody =>
      'Import a UDDF log from your dive computer or Subsurface, or add a dive by hand. Your logbook stays on this device.';

  @override
  String get importLog => 'Import log';

  @override
  String linkedMediaCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count linked media',
      one: '1 linked media item',
    );
    return '$_temp0';
  }

  @override
  String get noSitePositions =>
      'No dive site has a position yet. Add latitude and longitude to a dive to see it here.';

  @override
  String get diveSite => 'Dive site';

  @override
  String diveCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dives',
      one: '1 dive',
    );
    return '$_temp0';
  }

  @override
  String get importUddfLog => 'Import UDDF log';

  @override
  String get linkPhotosByTime => 'Link photos by capture time';

  @override
  String get exportGpx => 'Export GPX';

  @override
  String get exportUddf => 'Export UDDF';

  @override
  String get exportGeoJson => 'Export GeoJSON';

  @override
  String get logImported => 'Log imported';

  @override
  String logImportedBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new dives were added.',
      one: '1 new dive was added.',
      zero: 'Every dive in this log is already in your logbook.',
    );
    return '$_temp0';
  }

  @override
  String get cannotImportFile => 'Can’t import this file';

  @override
  String get noDiveTimes => 'No dive times';

  @override
  String get noDiveTimesBody =>
      'Dives need a start time and duration to match photos.';

  @override
  String get photosLinked => 'Photos linked';

  @override
  String photosLinkedBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos and videos were linked to their dives.',
      zero: 'No new photos or videos were taken during your dives.',
    );
    return '$_temp0';
  }

  @override
  String get cannotReadPhotoLibrary => 'Can’t read the photo library';

  @override
  String get editDive => 'Edit dive';

  @override
  String get newDive => 'New dive';

  @override
  String get save => 'Save';

  @override
  String get diveNumber => 'Number';

  @override
  String get site => 'Site';

  @override
  String get latitude => 'Latitude';

  @override
  String get longitude => 'Longitude';

  @override
  String get maxDepthMeters => 'Max depth (m)';

  @override
  String get durationMinutes => 'Duration (min)';

  @override
  String get waterTemperatureCelsius => 'Water temperature (°C)';

  @override
  String get buddy => 'Buddy';

  @override
  String get notes => 'Notes';

  @override
  String get deleteDive => 'Delete dive';

  @override
  String get dateAndTime => 'Date and time';

  @override
  String dateAndTimeValue(String date) {
    return 'Date and time, $date';
  }

  @override
  String get checkPosition => 'Check the position';

  @override
  String get checkPositionBody =>
      'Enter both latitude (−90 to 90) and longitude (−180 to 180) in decimal degrees, or leave both empty.';

  @override
  String get deleteDiveTitle => 'Delete this dive?';

  @override
  String get deleteDiveBody =>
      'Its photos and videos stay where they are; only the log entry is removed.';

  @override
  String get date => 'Date';

  @override
  String get notSet => 'Not set';

  @override
  String get position => 'Position';

  @override
  String get maxDepth => 'Max depth';

  @override
  String get duration => 'Duration';

  @override
  String get waterTemperature => 'Water temperature';

  @override
  String get profile => 'Profile';

  @override
  String depthReadings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count depth readings',
      one: '1 depth reading',
    );
    return '$_temp0';
  }

  @override
  String get photosAndVideos => 'Photos and videos';

  @override
  String get nothingLinked =>
      'Nothing linked yet. Linked media stays where it is; the logbook never copies it.';

  @override
  String get makeMovieFromDive => 'Make a movie from this dive';

  @override
  String get addPhotosAndVideos => 'Add photos and videos';

  @override
  String get findInPhotos => 'Find in Photos';

  @override
  String mediaDepthSuffix(String depth) {
    return ', $depth deep';
  }

  @override
  String get removeFromDive => 'Remove from dive';

  @override
  String get somethingWentWrong => 'Something went wrong';

  @override
  String diveMediaLinkedBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos and videos were linked.',
      one: '1 photo or video was linked.',
      zero: 'No new photos or videos from this dive were found.',
    );
    return '$_temp0';
  }

  @override
  String get mediaNotFound => 'Media not found';

  @override
  String get mediaNotFoundBody =>
      'None of the linked photos or videos can be opened. They may have been moved or deleted.';

  @override
  String diveSiteNamed(String name) {
    return 'Dive site $name';
  }

  @override
  String get osmAttributionSemantics =>
      'Map data © OpenStreetMap contributors. Show license.';

  @override
  String get osmAttribution => '© OpenStreetMap contributors';

  @override
  String get diveTitleUnnamed => 'Dive';

  @override
  String diveTitleNumber(int number) {
    return 'Dive $number';
  }

  @override
  String diveTitleNumberSite(int number, String site) {
    return '#$number $site';
  }

  @override
  String coordinatePair(String latitude, String longitude) {
    return '$latitude, $longitude';
  }

  @override
  String get localExportsTitle => 'Local Exports';

  @override
  String get select => 'Select';

  @override
  String get exportsLoadFailed => 'Exports could not be loaded.';

  @override
  String get noLocalExports => 'No local exports yet.';

  @override
  String selectedCount(int count) {
    return '$count selected';
  }

  @override
  String get deselectAll => 'Deselect all';

  @override
  String get selectAll => 'Select all';

  @override
  String localExportCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count local exports',
      one: '1 local export',
    );
    return '$_temp0';
  }

  @override
  String get deleteAll => 'Delete all';

  @override
  String deleteCount(int count) {
    return 'Delete $count';
  }

  @override
  String shareSelectedExports(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Share the selected exports',
      one: 'Share the selected export',
    );
    return '$_temp0';
  }

  @override
  String shareCount(int count) {
    return 'Share $count';
  }

  @override
  String get deleteAllExportsTitle => 'Delete all local exports?';

  @override
  String deleteExportsTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count exports?',
      one: 'Delete 1 export?',
    );
    return '$_temp0';
  }

  @override
  String get deleteExportsBody =>
      'The local files and their settings sidecars will be deleted. Imported originals and copies in Photos are not affected.';

  @override
  String get someExportsNotDeleted => 'Some exports could not be deleted';

  @override
  String someExportsNotDeletedBody(int failures, int count) {
    return '$failures of $count files may have been moved or are currently unavailable.';
  }

  @override
  String get shareExport => 'Share export';

  @override
  String get deleteExport => 'Delete export';

  @override
  String get previewUnavailableShort => 'Preview unavailable.';

  @override
  String get deleteExportTitle => 'Delete local export?';

  @override
  String get deleteExportBody =>
      'The local file and its settings sidecar will be deleted. The imported original and any copy in Photos are not affected.';

  @override
  String get exportNotDeleted => 'Export could not be deleted';

  @override
  String get exportNotDeletedBody =>
      'The file may have been moved or is currently unavailable.';

  @override
  String get couldNotShare => 'Could not share';

  @override
  String get shareSheetUnavailable =>
      'The share sheet could not be opened on this device. The export is still in Local Exports.';

  @override
  String get exportedFileGone =>
      'The exported file is no longer available. It may have been deleted from Local Exports.';

  @override
  String get exportedFilesGone =>
      'The exported files are no longer available. They may have been deleted from Local Exports.';

  @override
  String get previewSize => 'Preview size';

  @override
  String get dragToResizePreview => 'Drag to resize preview';

  @override
  String get resetPreviewSize => 'Reset preview size';

  @override
  String get appIconLabel => 'AquaRecover app icon';

  @override
  String get skip => 'Skip';

  @override
  String get tourWelcomeTitle => 'Restore color with a clear workflow';

  @override
  String get tourWelcomeBody =>
      'AquaRecover keeps the process simple: choose media, refine the result, then decide where to export it.';

  @override
  String get tourImportTitle => 'One photo or a complete batch';

  @override
  String get tourImportBody =>
      'A single selection opens in the editor. Select several items and they stay together in a queue you can review at any time.';

  @override
  String get tourEditTitle => 'Edit, inspect, and compare';

  @override
  String get tourEditBody =>
      'Start with a preset, then fine-tune adjustments, crop, and LUT. Tap a value bubble to adjust it; Reset restores the preset value.';

  @override
  String get tourExportTitle => 'You choose when and where to save';

  @override
  String get tourExportBody =>
      'Importing and editing never create a saved copy. On export, choose one or more destinations for the finished media.';

  @override
  String get previousPage => 'Previous page';

  @override
  String get startEditing => 'Start editing';

  @override
  String get next => 'Next';

  @override
  String tutorialPageOf(int page, int count) {
    return 'Tutorial page $page of $count';
  }

  @override
  String get onDevicePrivacy =>
      'Your media is processed on this device. AquaRecover does not upload it to a service.';

  @override
  String get onePhoto => 'One photo';

  @override
  String get batch => 'Batch';

  @override
  String get tourOnePhotoHint => 'The photo opens directly in the editor.';

  @override
  String get tourBatchHint => 'Three items are ready in one editable queue.';

  @override
  String get tourPresetsHint => 'Choose a starting look.';

  @override
  String get tourAdjustHint => 'Fine-tune each value.';

  @override
  String get tourCropHint => 'Crop, rotate, and flip.';

  @override
  String get tourLutHint => 'Apply a finishing LUT.';

  @override
  String get originalSlashEdited => 'Original / Edited';

  @override
  String get tourCompareHint =>
      'Try Split, or press and hold the preview for the original.';

  @override
  String editorToolNamed(String tool) {
    return '$tool editor tool';
  }

  @override
  String exportDestinationNamed(String destination) {
    return '$destination export destination';
  }

  @override
  String get tourExportCallout =>
      'Only a confirmed export writes the finished file. Completed batch items then leave the queue.';
}
