import 'dart:convert';
import 'dart:io';

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
  static const MethodChannel _iosChannel = MethodChannel('aqua_recover/video');
  static final Set<Process> _runningProcesses = <Process>{};

  static bool isBackendSupportedForOperatingSystem(String operatingSystem) {
    return operatingSystem == 'ios' || operatingSystem == 'macos';
  }

  static bool get isBackendSupportedOnCurrentPlatform {
    return isBackendSupportedForOperatingSystem(Platform.operatingSystem);
  }

  static bool get isBackendAvailableOnCurrentPlatform {
    if (Platform.isIOS) return true;
    return isBackendSupportedOnCurrentPlatform &&
        _findFfmpegExecutable() != null;
  }

  static String get backendUnavailableReason {
    if (!isBackendSupportedOnCurrentPlatform) return unavailableMessage;
    if (Platform.isIOS) return unavailableMessage;
    return 'Video export requires an ffmpeg command-line binary on macOS. Photo recovery remains available.';
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
    if (Platform.isIOS) {
      return _restoreVideoOnIos(
        inputPath,
        settings,
        rawDescriptor: rawDescriptor,
        trim: trim,
        exportOptions: exportOptions,
        lutProfile: lutProfile,
      );
    }
    final ffmpeg = _findFfmpegExecutable();
    if (ffmpeg == null) throw StateError(backendUnavailableReason);

    final inputFile = File(inputPath);
    if (!await inputFile.exists()) {
      throw FileSystemException('Input video not found.', inputPath);
    }
    rawDescriptor?.validateForProcessing();
    trim.validate();

    final outputPath = await OutputPaths.forVideo(inputPath, extension: 'mp4');
    await File(outputPath).parent.create(recursive: true);
    final filters = settings
        .ffmpegFilters(extraFilters: LutService.videoFiltersFor(lutProfile))
        .join(',');
    final args = <String>['-hide_banner', '-nostdin', '-y'];
    if (rawDescriptor != null) args.addAll(rawDescriptor.toFfmpegInputArgs());
    args.addAll(trim.toFfmpegInputPrefixArgs());
    args.addAll(['-i', inputPath, '-map', '0:v:0']);
    if (exportOptions.keepAudio && rawDescriptor == null) {
      args.addAll(['-map', '0:a?']);
    }
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
    ]);
    if (exportOptions.keepAudio && rawDescriptor == null) {
      args.addAll(['-c:a', 'aac', '-b:a', '192k']);
    } else {
      args.add('-an');
    }
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

  Future<String> _restoreVideoOnIos(
    String inputPath,
    RestorationSettings settings, {
    RawVideoDescriptor? rawDescriptor,
    required VideoEditSettings trim,
    required ExportOptions exportOptions,
    required LutProfile lutProfile,
  }) async {
    if (rawDescriptor != null) {
      throw UnsupportedError(
        'RAW video export requires the macOS FFmpeg backend. Standard iPhone videos can be exported on iOS.',
      );
    }
    if (lutProfile.isCustomCube) {
      throw UnsupportedError(
        'Custom .cube LUT video export is not supported by the native iOS backend yet. Built-in looks and photo exports remain available.',
      );
    }
    final inputFile = File(inputPath);
    if (!await inputFile.exists()) {
      throw FileSystemException('Input video not found.', inputPath);
    }
    trim.validate();

    final outputPath = await OutputPaths.forVideo(inputPath, extension: 'mp4');
    await File(outputPath).parent.create(recursive: true);
    try {
      final exported = await _iosChannel.invokeMethod<String>('restoreVideo', {
        'inputPath': inputPath,
        'outputPath': outputPath,
        'settings': settings.toJson(),
        'trim': trim.toJson(),
        'exportOptions': exportOptions.toJson(),
        'lutProfile': lutProfile.toJson(),
      });
      if (exported == null || exported.isEmpty) {
        throw StateError(
          'Native iOS video export did not return an output path.',
        );
      }
      return exported;
    } on PlatformException catch (error) {
      throw StateError(
        'Native iOS video restoration failed. ${error.message ?? error.code}',
      );
    }
  }

  void cancelAll() {
    for (final process in _runningProcesses.toList()) {
      process.kill();
    }
    _runningProcesses.clear();
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
