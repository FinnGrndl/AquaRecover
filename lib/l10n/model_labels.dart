import 'dart:math' as math;

import '../core/models/export_options.dart';
import '../core/models/image_transform_settings.dart';
import '../core/models/lut_profile.dart';
import '../core/models/media_job.dart';
import '../core/models/media_kind.dart';
import '../core/models/restoration_settings.dart';
import '../core/photo/photo_library_service.dart';
import '../core/processing/scene_analyzer.dart';
import '../core/processing/video_restoration_service.dart';
import 'package:photo_manager/photo_manager.dart';

import 'l10n.dart';

// The core models keep English labels for logs and the MCP server. The app
// shows these localized ones instead.

extension RestorationPresetL10n on RestorationPreset {
  String labelIn(AppLocalizations l10n) => switch (this) {
    RestorationPreset.none => l10n.presetNone,
    RestorationPreset.auto => l10n.presetAuto,
    RestorationPreset.natural => l10n.presetNatural,
    RestorationPreset.vivid => l10n.presetVivid,
    RestorationPreset.deep => l10n.presetDeep,
    RestorationPreset.macro => l10n.presetMacro,
    RestorationPreset.shallow => l10n.presetShallow,
    RestorationPreset.greenWater => l10n.presetGreenWater,
    RestorationPreset.redFilter => l10n.presetRedFilter,
    RestorationPreset.artificialLight => l10n.presetArtificialLight,
  };

  String helpIn(AppLocalizations l10n) => switch (this) {
    RestorationPreset.none => l10n.presetNoneHelp,
    RestorationPreset.auto => l10n.presetAutoHelp,
    RestorationPreset.natural => l10n.presetNaturalHelp,
    RestorationPreset.vivid => l10n.presetVividHelp,
    RestorationPreset.deep => l10n.presetDeepHelp,
    RestorationPreset.macro => l10n.presetMacroHelp,
    RestorationPreset.shallow => l10n.presetShallowHelp,
    RestorationPreset.greenWater => l10n.presetGreenWaterHelp,
    RestorationPreset.redFilter => l10n.presetRedFilterHelp,
    RestorationPreset.artificialLight => l10n.presetArtificialLightHelp,
  };
}

extension MediaKindL10n on MediaKind {
  String labelIn(AppLocalizations l10n) => switch (this) {
    MediaKind.photo => l10n.mediaKindPhoto,
    MediaKind.rawPhoto => l10n.mediaKindRawPhoto,
    MediaKind.video => l10n.mediaKindVideo,
    MediaKind.rawVideo => l10n.mediaKindRawVideo,
  };
}

extension MediaSourceL10n on MediaSource {
  String labelIn(AppLocalizations l10n) => switch (this) {
    MediaSource.files => l10n.destinationFiles,
    MediaSource.photos => l10n.destinationPhotos,
  };
}

extension JobStatusL10n on JobStatus {
  String labelIn(AppLocalizations l10n) => switch (this) {
    JobStatus.pending => l10n.jobStatusReady,
    JobStatus.processing => l10n.jobStatusProcessing,
    JobStatus.complete => l10n.jobStatusComplete,
    JobStatus.failed => l10n.jobStatusFailed,
  };
}

extension BeforeAfterLayoutL10n on BeforeAfterLayout {
  String labelIn(AppLocalizations l10n) => switch (this) {
    BeforeAfterLayout.sideBySide => l10n.beforeAfterSideBySide,
    BeforeAfterLayout.split => l10n.beforeAfterSplit,
  };
}

extension ExportPresetL10n on ExportPreset {
  String labelIn(AppLocalizations l10n) => switch (this) {
    ExportPreset.social => l10n.exportPresetSocial,
    ExportPreset.archive => l10n.exportPresetArchive,
    ExportPreset.proEdit => l10n.exportPresetProEdit,
  };
}

extension LutProfileL10n on LutProfile {
  /// The built-in looks by their localized name; a custom `.cube` keeps
  /// the name it was imported with.
  String nameIn(AppLocalizations l10n) => switch (kind) {
    LutKind.none => l10n.lutNone,
    LutKind.coralWarm => l10n.lutCoralWarm,
    LutKind.blueWater => l10n.lutBlueWater,
    LutKind.greenWater => l10n.lutGreenWater,
    LutKind.customCube => name,
  };
}

extension CropAspectRatioL10n on CropAspectRatio {
  String labelIn(AppLocalizations l10n) => switch (this) {
    CropAspectRatio.original => l10n.cropOriginal,
    CropAspectRatio.freeform => l10n.cropFree,
    CropAspectRatio.square => l10n.cropSquare,
    _ => label,
  };
}

extension WaterTypeL10n on WaterType {
  String labelIn(AppLocalizations l10n) => switch (this) {
    WaterType.blue => l10n.waterBlue,
    WaterType.green => l10n.waterGreen,
    WaterType.neutral => l10n.waterNeutral,
  };
}

extension SceneAnalysisL10n on SceneAnalysis {
  /// The main reason for the suggested preset, or null when there is none.
  String? reasonIn(AppLocalizations l10n) {
    if (reasons.isEmpty) return null;
    return switch (suggestedPreset) {
      RestorationPreset.artificialLight => l10n.reasonArtificialLight,
      RestorationPreset.redFilter => l10n.reasonRedFilter,
      RestorationPreset.natural => l10n.reasonNatural,
      RestorationPreset.greenWater => l10n.reasonGreenWater(
        l10n.decimal(meanB / math.max(1.0, meanG), digits: 2),
      ),
      RestorationPreset.deep => l10n.reasonDeep,
      RestorationPreset.shallow => l10n.reasonShallow,
      RestorationPreset.auto => l10n.reasonAuto,
      RestorationPreset.none ||
      RestorationPreset.vivid ||
      RestorationPreset.macro => reasons.first,
    };
  }
}

extension PhotoLibraryPermissionL10n on PhotoLibraryPermissionException {
  String messageIn(AppLocalizations l10n) => switch (state) {
    PermissionState.denied => l10n.photosAccessDenied,
    PermissionState.restricted => l10n.photosAccessRestricted,
    PermissionState.notDetermined => l10n.photosAccessNotDetermined,
    PermissionState.authorized ||
    PermissionState.limited => l10n.photosAccessAvailable,
  };
}

/// [error] as text for an alert or status line.
///
/// Messages the app itself raises for the user, such as a missing video
/// backend, are translated. Other failures keep their technical English
/// detail, which is also what a bug report needs.
String localizedErrorMessage(AppLocalizations l10n, Object error) {
  if (error is PhotoLibraryPermissionException) return error.messageIn(l10n);
  final raw = switch (error) {
    StateError(:final message) => message,
    FormatException(:final message) => message,
    _ => null,
  };
  final known = raw == null ? null : localizedKnownMessage(l10n, raw);
  final message =
      known ?? error.toString().replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  return message.length <= 260 ? message : '${message.substring(0, 260)}...';
}

/// The translation of an English message raised by the core services, or
/// null when the app has none.
String? localizedKnownMessage(
  AppLocalizations l10n,
  String message,
) => switch (message) {
  VideoRestorationService.unavailableMessage => l10n.videoUnavailableBuild,
  VideoRestorationService.iosMissingBackendMessage => l10n.videoUnavailableIos,
  VideoRestorationService.macosMissingBackendMessage =>
    l10n.videoUnavailableMacos,
  VideoRestorationService.rawVideoNeedsFfmpegMessage =>
    l10n.videoRawNeedsFfmpeg,
  VideoRestorationService.windowsNeedsFfmpegMessage =>
    l10n.videoWindowsNeedsFfmpeg,
  'Photos permission was not granted.' => l10n.photosPermissionDenied,
  'The Photos picker failed.' => l10n.photosPickerFailed,
  'The selected Photos item is not available locally. Open it in Photos '
      'to download the original from iCloud, then import it again.' =>
    l10n.photosItemNotLocal,
  'The selected Photos item could not be read from local storage. Choose '
      'another item or download the original first.' =>
    l10n.photosItemUnreadable,
  'RAW video dimensions are too small.' => l10n.rawVideoTooSmall,
  'The exported file is no longer available. It may have been deleted '
      'from Local Exports.' =>
    l10n.exportedFileGone,
  'The exported files are no longer available. They may have been '
      'deleted from Local Exports.' =>
    l10n.exportedFilesGone,
  'Add at least one photo or clip to the timeline.' => l10n.timelineEmptyError,
  'Trim start must be zero or greater.' => l10n.trimStartNegative,
  'Trim start must be less than 24 hours.' => l10n.trimStartTooLate,
  'Trim end must be after trim start.' => l10n.trimEndBeforeStart,
  'Trim end must be less than 24 hours.' => l10n.trimEndTooLate,
  _ => null,
};
