import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../models/export_options.dart';
import '../models/lut_profile.dart';
import '../models/raw_video_descriptor.dart';
import '../models/restoration_settings.dart';
import '../models/video_edit_settings.dart';
import '../utils/output_paths.dart';
import 'ffmpeg_video_backend.dart';
import 'lut_service.dart';
import 'video_lut_baker.dart';

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
  static const windowsNeedsFfmpegMessage =
      'Video export on Windows needs ffmpeg. Install it (for example with "winget install ffmpeg"), restart AquaRecover, and try again. Photo recovery remains available.';
  static const MethodChannel _nativeChannel = MethodChannel(
    'aqua_recover/video',
  );
  static final Set<Process> _runningProcesses = <Process>{};

  /// Bumped by [cancelAll] so a job still sampling frames or baking its
  /// colour table stops before the export starts.
  static int _cancelGeneration = 0;

  /// Which renderer exports video on [operatingSystem].
  ///
  /// iOS and macOS share one AVFoundation + Core Image renderer
  /// (`AquaMediaPipeline.swift`). Android (Media3) and Windows (`ffmpeg`)
  /// apply a colour table baked from the same restoration by
  /// [VideoLutBaker].
  static VideoBackend backendFor(
    String operatingSystem, {
    bool ffmpegAvailable = false,
  }) => switch (operatingSystem) {
    'ios' || 'macos' => VideoBackend.appleNative,
    'android' => VideoBackend.androidMedia3,
    'windows' when ffmpegAvailable => VideoBackend.ffmpegLut,
    _ => VideoBackend.none,
  };

  static VideoBackend get currentBackend => backendFor(
    Platform.operatingSystem,
    ffmpegAvailable: Platform.isWindows && FfmpegVideoBackend.locate() != null,
  );

  static bool usesNativeBackendForOperatingSystem(String operatingSystem) =>
      backendFor(operatingSystem) == VideoBackend.appleNative;

  static bool isBackendSupportedForOperatingSystem(String operatingSystem) =>
      backendFor(operatingSystem, ffmpegAvailable: true) != VideoBackend.none;

  static bool get isBackendSupportedOnCurrentPlatform {
    return isBackendSupportedForOperatingSystem(Platform.operatingSystem);
  }

  static bool isBackendAvailableForOperatingSystem(
    String operatingSystem, {
    bool ffmpegAvailable = false,
  }) =>
      backendFor(operatingSystem, ffmpegAvailable: ffmpegAvailable) !=
      VideoBackend.none;

  static bool get isBackendAvailableOnCurrentPlatform =>
      currentBackend != VideoBackend.none;

  static bool get canCancelRunningJobsOnCurrentPlatform =>
      currentBackend != VideoBackend.none;

  static String get backendUnavailableReason {
    if (!isBackendSupportedOnCurrentPlatform) return unavailableMessage;
    if (Platform.isIOS) return iosMissingBackendMessage;
    if (Platform.isMacOS) return macosMissingBackendMessage;
    if (Platform.isWindows) return windowsNeedsFfmpegMessage;
    return unavailableMessage;
  }

  /// Media3 Transformer writes MP4 only, so Android always exports MP4.
  static VideoOutputFormat outputFormatFor(
    VideoBackend backend,
    VideoOutputFormat requested,
  ) =>
      backend == VideoBackend.androidMedia3 ? VideoOutputFormat.mp4 : requested;

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
    final backend = currentBackend;
    if (rawDescriptor == null && backend != VideoBackend.appleNative) {
      return _restoreVideoWithBakedLut(
        backend,
        inputPath,
        settings,
        trim: trim,
        exportOptions: exportOptions,
        lutProfile: lutProfile,
      );
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
    final ffmpeg = FfmpegVideoBackend.locate();
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
          'Video restoration failed with FFmpeg exit $exitCode. ${FfmpegVideoBackend.redactLog(log, inputPath, outputPath)}',
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

  Future<String> _restoreVideoWithBakedLut(
    VideoBackend backend,
    String inputPath,
    RestorationSettings settings, {
    required VideoEditSettings trim,
    required ExportOptions exportOptions,
    required LutProfile lutProfile,
  }) async {
    if (backend == VideoBackend.none) {
      throw StateError(backendUnavailableReason);
    }
    if (!await File(inputPath).exists()) {
      throw FileSystemException('Input video not found.', inputPath);
    }
    trim.validate();
    final format = outputFormatFor(backend, exportOptions.videoFormat);
    final outputPath = await OutputPaths.forVideo(
      inputPath,
      extension: format.extension,
      temporary: !exportOptions.keepLocalCopy,
    );
    await File(outputPath).parent.create(recursive: true);

    final generation = _cancelGeneration;
    void checkNotCancelled() {
      if (generation != _cancelGeneration) throw const VideoExportCancelled();
    }

    if (backend == VideoBackend.ffmpegLut) {
      final ffmpeg = FfmpegVideoBackend(FfmpegVideoBackend.locate()!);
      final frames = await ffmpeg.sampleFrames(inputPath, trim: trim);
      checkNotCancelled();
      final cube = await VideoLutBaker.bakeFromEncodedFrames(
        frames,
        settings,
        lutProfile: lutProfile,
      );
      checkNotCancelled();
      Process? running;
      try {
        await ffmpeg.export(
          inputPath: inputPath,
          outputPath: outputPath,
          cube: cube,
          trim: trim,
          exportOptions: exportOptions,
          onStarted: (process) => _runningProcesses.add(running = process),
        );
      } on StateError {
        checkNotCancelled();
        rethrow;
      } finally {
        _runningProcesses.remove(running);
      }
      return outputPath;
    }

    try {
      final frames = await _nativeChannel
          .invokeListMethod<Uint8List>('sampleFrames', {
            'inputPath': inputPath,
            'count': 5,
            'maxDimension': VideoLutBaker.sampleMaxDimension,
            if (trim.hasTrim) 'startSeconds': trim.startSeconds,
            if (trim.hasTrim) 'endSeconds': trim.endSeconds,
          });
      final cube = await VideoLutBaker.bakeFromEncodedFrames(
        frames ?? const [],
        settings,
        lutProfile: lutProfile,
      );
      final exported = await _nativeChannel
          .invokeMethod<String>('exportWithLut', {
            'inputPath': inputPath,
            'outputPath': outputPath,
            'lutSize': cube.size,
            'lut': cube.toArgb(),
            'keepAudio': exportOptions.keepAudio,
            if (trim.hasTrim) 'startSeconds': trim.startSeconds,
            if (trim.hasTrim) 'endSeconds': trim.endSeconds,
          });
      if (exported == null || exported.isEmpty) {
        throw StateError('Android video export did not return an output path.');
      }
      return exported;
    } on MissingPluginException {
      throw StateError(unavailableMessage);
    } on PlatformException catch (error) {
      if (error.code == 'CANCELLED') throw const VideoExportCancelled();
      throw StateError(
        'Android video restoration failed. ${error.message ?? error.code}',
      );
    }
  }

  void cancelAll() {
    _cancelGeneration++;
    for (final process in _runningProcesses.toList()) {
      process.kill();
    }
    _runningProcesses.clear();
    if (Platform.isIOS || Platform.isMacOS || Platform.isAndroid) {
      _nativeChannel.invokeMethod<void>('cancelRestoreVideo').catchError((
        Object _,
      ) {
        // Older runners without cancel support finish the export instead.
      });
    }
  }
}

/// Thrown when the user cancelled a native video export.
class VideoExportCancelled implements Exception {
  const VideoExportCancelled();

  @override
  String toString() => 'Video export was cancelled.';
}

enum VideoBackend {
  /// AVFoundation + Core Image on iOS and macOS.
  appleNative,

  /// Media3 Transformer with a baked colour table on Android.
  androidMedia3,

  /// A local `ffmpeg` with a baked colour table, on Windows.
  ffmpegLut,

  /// No video export on this platform or build.
  none,
}
