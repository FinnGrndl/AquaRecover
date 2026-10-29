import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// What happened after the share sheet closed.
enum ShareOutcome {
  /// The person picked an app or action.
  shared,

  /// The person closed the sheet without sharing.
  dismissed,

  /// The platform does not report what the person chose.
  unknown,
}

/// Hands exported files to the system share sheet (AirDrop, Messages, Mail,
/// WhatsApp, Instagram and so on). Nothing leaves the device unless the
/// person taps Share and then chooses an app; that app receives the files.
class ShareService {
  const ShareService();

  /// First Windows 10 build (1809) whose share UI accepts files. Older
  /// builds only offer a mailto fallback without attachments.
  static const windowsFileShareBuild = 17763;

  /// Whether [operatingSystem] can share files through a system sheet.
  ///
  /// Linux has no file share sheet, and Windows only from build 1809. A
  /// Windows version string without a build number counts as supported,
  /// since Flutter itself needs Windows 10.
  static bool supportsFileSharing({
    required String operatingSystem,
    String operatingSystemVersion = '',
  }) => switch (operatingSystem) {
    'ios' || 'android' || 'macos' => true,
    'windows' =>
      (windowsBuild(operatingSystemVersion) ?? windowsFileShareBuild) >=
          windowsFileShareBuild,
    _ => false,
  };

  /// Reads the build number from a Windows `Platform.operatingSystemVersion`
  /// such as `"Windows 10 Pro" 10.0 (Build 19045)`.
  static int? windowsBuild(String operatingSystemVersion) {
    final match = RegExp(
      r'Build (\d+)',
      caseSensitive: false,
    ).firstMatch(operatingSystemVersion);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// Whether a Share button should be offered on this device.
  bool get isAvailable => supportsFileSharing(
    operatingSystem: Platform.operatingSystem,
    operatingSystemVersion: Platform.operatingSystemVersion,
  );

  /// Opens the share sheet for [paths]. [origin] is the tapped control's
  /// rectangle in global coordinates: the iPad and Mac sheets are popovers
  /// that point at it.
  ///
  /// Files that no longer exist are skipped. Throws a [StateError] when none
  /// of them is left.
  Future<ShareOutcome> shareFiles(
    List<String> paths, {
    required Rect? origin,
  }) async {
    final files = [
      for (final path in paths)
        if (File(path).existsSync()) XFile(path),
    ];
    if (files.isEmpty) {
      throw StateError(
        paths.length == 1
            ? 'The exported file is no longer available. It may have been deleted from Local Exports.'
            : 'The exported files are no longer available. They may have been deleted from Local Exports.',
      );
    }
    final result = await SharePlus.instance.share(
      ShareParams(files: files, sharePositionOrigin: origin),
    );
    return switch (result.status) {
      ShareResultStatus.success => ShareOutcome.shared,
      ShareResultStatus.dismissed => ShareOutcome.dismissed,
      ShareResultStatus.unavailable => ShareOutcome.unknown,
    };
  }
}

/// The global rectangle of the control that [context] belongs to, for the
/// share sheet's popover anchor. Wrap the button in a [Builder] so the
/// context is the button's own, not the page's.
Rect? shareOriginOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
