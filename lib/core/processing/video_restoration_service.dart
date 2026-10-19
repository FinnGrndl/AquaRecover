import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/export_options.dart';
import '../models/lut_profile.dart';
import '../models/raw_video_descriptor.dart';
import '../models/restoration_settings.dart';
import '../models/video_edit_settings.dart';
import '../utils/output_paths.dart';
import 'lut_service.dart';

class VideoRestorationService {
  const VideoRestorationService();

  static const unavailableMessage =
      'Video export is not available in this build. Photo recovery remains available.';
  static const iosMissingBackendMessage =
      'Native iOS video export is missing from this build. Rebuild the iOS runner or run the bootstrap script, then try again.';
  static const macosMissingBackendMessage =
      'Native macOS video export is missing from this build. Rebuild the macOS runner or run the bootstrap script, then try again.';
  static const rawVideoNeedsFfmpegMessage =
      'RAW video export needs an ffmpeg command-line binary, which a sandboxed macOS app cannot launch. Standard MP4 and MOV clips export natively.';
  static const MethodChannel _nativeChannel = MethodChannel(
    'aqua_recover/video',
  );
  static final Set<Process> _runningProcesses = <Process>{};

  /// iOS and macOS share one AVFoundation + Core Image renderer
  /// (`AquaMediaPipeline.swift`), so both export natively.
  static bool usesNativeBackendForOperatingSystem(String operatingSystem) =>
      operatingSystem == 'ios' || operatingSystem == 'macos';

  static bool isBackendSupportedForOperatingSystem(String operatingSystem) {
    return usesNativeBackendForOperatingSystem(operatingSystem);
  }

  static bool get isBackendSupportedOnCurrentPlatform {
    return isBackendSupportedForOperatingSystem(Platform.operatingSystem);
  }

  static bool isBackendAvailableForOperatingSystem(String operatingSystem) {
    return usesNativeBackendForOperatingSystem(operatingSystem);
  }

  static bool get isBackendAvailableOnCurrentPlatform {
    return isBackendAvailableForOperatingSystem(Platform.operatingSystem);
  }

  static bool get canCancelRunningJobsOnCurrentPlatform {
    return usesNativeBackendForOperatingSystem(Platform.operatingSystem);
  }

  static String get backendUnavailableReason {
    if (!isBackendSupportedOnCurrentPlatform) return unavailableMessage;
    if (Platform.isIOS) return iosMissingBackendMessage;
    return macosMissingBackendMessage;
  }

  Future<String> restoreVideo(
    String inputPath,
    RestorationSettings settings, {
    RawVideoDescriptor? rawDescriptor,
    VideoEditSettings trim = const VideoEditSettings(),
    ExportOptions exportOptions = const ExportOptions(),
    LutProfile lutProfile = LutProfile.none,
  }) async {
    if (!isBackendSupportedOnCurrentPlatform) {
      throw UnsupportedError(unavailableMessage);
    }
    if (rawDescriptor == null) {
      return _restoreVideoNatively(
        inputPath,
        settings,
        trim: trim,
        exportOptions: exportOptions,
        lutProfile: lutProfile,
      );
    }
    if (!Platform.isMacOS) {
      throw UnsupportedError(
        'RAW video export requires the macOS FFmpeg backend. Standard iPhone videos can be exported on iOS.',
      );
    }
    final ffmpeg = _findFfmpegExecutable();
    if (ffmpeg == null) throw StateError(rawVideoNeedsFfmpegMessage);

    final inputFile = File(inputPath);
    if (!await inputFile.exists()) {
      throw FileSystemException('Input video not found.', inputPath);
    }
    rawDescriptor.validateForProcessing();
    trim.validate();

    final outputPath = await OutputPaths.forVideo(
      inputPath,
      extension: exportOptions.videoFormat.extension,
      temporary: !exportOptions.keepLocalCopy,
    );
    await File(outputPath).parent.create(recursive: true);
    final filters = settings
        .ffmpegFilters(extraFilters: LutService.videoFiltersFor(lutProfile))
        .join(',');
    final args = <String>['-hide_banner', '-nostdin', '-y'];
    args.addAll(rawDescriptor.toFfmpegInputArgs());
    args.addAll(trim.toFfmpegInputPrefixArgs());
    args.addAll(['-i', inputPath, '-map', '0:v:0']);
    if (exportOptions.stripMetadata) args.addAll(['-map_metadata', '-1']);
    args.addAll([
      '-vf',
      filters,
      '-c:v',
      'libx264',
      '-preset',
      'medium',
      '-crf',
      '18',
      '-pix_fmt',
      'yuv420p',
      '-an',
    ]);
    args.addAll(trim.toFfmpegOutputArgs());
    args.addAll(['-movflags', '+faststart', outputPath]);

    final process = await Process.start(ffmpeg, args);
    _runningProcesses.add(process);
    try {
      final stdout = process.stdout.transform(utf8.decoder).join();
      final stderr = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode;
      final log = '${await stdout} ${await stderr}'.trim();
      if (exitCode != 0) {
        throw StateError(
          'Video restoration failed with FFmpeg exit $exitCode. ${_safeLog(log, inputPath, outputPath)}',
        );
      }
    } finally {
      _runningProcesses.remove(process);
    }
    return outputPath;
  }

  Future<String> _restoreVideoNatively(
    String inputPath,
    RestorationSettings settings, {
    required VideoEditSettings trim,
    required ExportOptions exportOptions,
    required LutProfile lutProfile,
  }) async {
    final inputFile = File(inputPath);
    if (!await inputFile.exists()) {
      throw FileSystemException('Input video not found.', inputPath);
    }
    trim.validate();

    final outputPath = await OutputPaths.forVideo(
      inputPath,
      extension: exportOptions.videoFormat.extension,
      temporary: !exportOptions.keepLocalCopy,
    );
    await File(outputPath).parent.create(recursive: true);
    try {
      final exported = await _nativeChannel.invokeMethod<String>(
        'restoreVideo',
        nativeArguments(
          inputPath: inputPath,
          outputPath: outputPath,
          settings: settings,
          trim: trim,
          exportOptions: exportOptions,
          lutProfile: lutProfile,
        ),
      );
      if (exported == null || exported.isEmpty) {
        throw StateError('Native video export did not return an output path.');
      }
      return exported;
    } on MissingPluginException {
      throw StateError(backendUnavailableReason);
    } on PlatformException catch (error) {
      if (error.code == 'CANCELLED') {
        throw const VideoExportCancelled();
      }
      throw StateError(
        'Native video restoration failed. ${error.message ?? error.code}',
      );
    }
  }

  /// Arguments for the `aqua_recover/video` `restoreVideo` call. Custom
  /// `.cube` LUTs travel as a path; the native side parses and caches them.
  @visibleForTesting
  static Map<String, Object?> nativeArguments({
    required String inputPath,
    required String outputPath,
    required RestorationSettings settings,
    required VideoEditSettings trim,
    required ExportOptions exportOptions,
    required LutProfile lutProfile,
  }) => {
    'inputPath': inputPath,
    'outputPath': outputPath,
    'settings': settings.toJson(),
    'trim': trim.toJson(),
    'exportOptions': exportOptions.toJson(),
    'lutProfile': lutProfile.toJson(),
  };

  void cancelAll() {
    for (final process in _runningProcesses.toList()) {
      process.kill();
    }
    _runningProcesses.clear();
    if (usesNativeBackendForOperatingSystem(Platform.operatingSystem)) {
      _nativeChannel.invokeMethod<void>('cancelRestoreVideo').catchError((
        Object _,
      ) {
        // Older runners without cancel support finish the export instead.
      });
    }
  }

  static String? _findFfmpegExecutable() {
    const candidates = <String>[
      '/opt/homebrew/bin/ffmpeg',
      '/usr/local/bin/ffmpeg',
      '/usr/bin/ffmpeg',
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    try {
      final result = Process.runSync('/usr/bin/which', const ['ffmpeg']);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim().split('\n').first;
        if (path.isNotEmpty && File(path).existsSync()) return path;
      }
    } on Object {
      return null;
    }
    return null;
  }

  static String _safeLog(String log, String inputPath, String outputPath) {
    final redacted = log
        .replaceAll(inputPath, p.basename(inputPath))
        .replaceAll(outputPath, p.basename(outputPath))
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
    if (redacted.isEmpty) return 'No FFmpeg log was returned.';
    return redacted.length > 2000
        ? '${redacted.substring(0, 2000)}...'
        : redacted;
  }
}

/// Thrown when the user cancelled a native video export.
class VideoExportCancelled implements Exception {
  const VideoExportCancelled();

  @override
  String toString() => 'Video export was cancelled.';
}
