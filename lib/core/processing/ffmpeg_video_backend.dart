import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/export_options.dart';
import '../models/video_edit_settings.dart';
import 'video_lut_baker.dart';

/// Video export through a locally installed `ffmpeg`, used on Windows.
///
/// Colour work happens in a baked [ColorCube] applied with `lut3d`, the same
/// table Android renders, so both platforms match the still renderer on flat
/// regions. No FFmpeg binary is bundled.
class FfmpegVideoBackend {
  const FfmpegVideoBackend(this.ffmpeg);

  final String ffmpeg;

  static String? _cachedPath;
  static bool _searched = false;

  /// Finds `ffmpeg` in common install locations and on `PATH`. The result is
  /// cached for the life of the process.
  static String? locate() {
    if (_searched) return _cachedPath;
    _searched = true;
    return _cachedPath = _search();
  }

  static String? _search() {
    final env = Platform.environment;
    final candidates = <String>[
      if (Platform.isWindows) ...[
        if (env['LOCALAPPDATA'] case final local?)
          p.join(local, 'Microsoft', 'WinGet', 'Links', 'ffmpeg.exe'),
        if (env['USERPROFILE'] case final home?)
          p.join(home, 'scoop', 'shims', 'ffmpeg.exe'),
        r'C:\ProgramData\chocolatey\bin\ffmpeg.exe',
        if (env['ProgramFiles'] case final programs?)
          p.join(programs, 'ffmpeg', 'bin', 'ffmpeg.exe'),
        r'C:\ffmpeg\bin\ffmpeg.exe',
      ] else ...[
        '/opt/homebrew/bin/ffmpeg',
        '/usr/local/bin/ffmpeg',
        '/usr/bin/ffmpeg',
      ],
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    try {
      final result = Platform.isWindows
          ? Process.runSync('where', const ['ffmpeg'])
          : Process.runSync('/usr/bin/which', const ['ffmpeg']);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim().split(RegExp(r'\r?\n'));
        if (path.first.isNotEmpty && File(path.first).existsSync()) {
          return path.first;
        }
      }
    } on Object {
      return null;
    }
    return null;
  }

  /// Reads the container duration from ffmpeg's input banner.
  Future<double?> durationSeconds(String inputPath) async =>
      (await probe(inputPath)).duration;

  /// Duration and whether the file has an audio stream, from ffmpeg's input
  /// banner. Works without `ffprobe`, which many Windows installs lack.
  Future<({double? duration, bool hasAudio})> probe(String inputPath) async {
    final result = await Process.run(
      ffmpeg,
      ['-hide_banner', '-nostdin', '-i', inputPath],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    final banner = result.stderr as String;
    return (
      duration: parseDuration(banner),
      hasAudio: RegExp(r'Stream #\d+:\d+.*: Audio:').hasMatch(banner),
    );
  }

  /// One downscaled PNG of a still image (any format ffmpeg decodes).
  Future<Uint8List> stillFrame(
    String imagePath, {
    int maxDimension = VideoLutBaker.sampleMaxDimension,
  }) async {
    final result = await Process.run(ffmpeg, [
      '-hide_banner',
      '-nostdin',
      '-loglevel',
      'error',
      '-i',
      imagePath,
      '-frames:v',
      '1',
      '-vf',
      'scale=$maxDimension:$maxDimension:force_original_aspect_ratio=decrease',
      '-f',
      'image2pipe',
      '-c:v',
      'png',
      '-',
    ], stdoutEncoding: null);
    final bytes = result.stdout as List<int>;
    if (result.exitCode != 0 || bytes.isEmpty) {
      throw StateError('FFmpeg could not decode ${p.basename(imagePath)}.');
    }
    return Uint8List.fromList(bytes);
  }

  static double? parseDuration(String banner) {
    final match = RegExp(
      r'Duration:\s*(\d+):(\d{2}):(\d{2}(?:\.\d+)?)',
    ).firstMatch(banner);
    if (match == null) return null;
    return int.parse(match.group(1)!) * 3600 +
        int.parse(match.group(2)!) * 60 +
        double.parse(match.group(3)!);
  }

  /// PNG frames from the middle of [count] equal slices of the trimmed range.
  Future<List<Uint8List>> sampleFrames(
    String inputPath, {
    VideoEditSettings trim = const VideoEditSettings(),
    int count = 5,
    int maxDimension = VideoLutBaker.sampleMaxDimension,
  }) async {
    final duration = await durationSeconds(inputPath) ?? 0;
    final start = trim.hasTrim ? trim.startSeconds : 0.0;
    final end = trim.hasTrim && trim.endSeconds != null
        ? trim.endSeconds!.clamp(start, duration > 0 ? duration : start)
        : duration;
    final frames = <Uint8List>[];
    for (var i = 0; i < count; i++) {
      final time = start + (end - start) * (2 * i + 1) / (2 * count);
      final result = await Process.run(ffmpeg, [
        '-hide_banner',
        '-nostdin',
        '-loglevel',
        'error',
        '-ss',
        time.toStringAsFixed(3),
        '-i',
        inputPath,
        '-frames:v',
        '1',
        '-vf',
        'scale=$maxDimension:$maxDimension:force_original_aspect_ratio=decrease',
        '-f',
        'image2pipe',
        '-c:v',
        'png',
        '-',
      ], stdoutEncoding: null);
      final bytes = result.stdout as List<int>;
      if (result.exitCode == 0 && bytes.isNotEmpty) {
        frames.add(Uint8List.fromList(bytes));
      }
    }
    if (frames.isEmpty) {
      throw StateError('FFmpeg could not read any frame from the video.');
    }
    return frames;
  }

  /// Arguments for the export, relative to a working directory that holds
  /// `restore.cube`, so the filter graph never needs path escaping.
  static List<String> exportArguments({
    required String inputPath,
    required String outputPath,
    required VideoEditSettings trim,
    required ExportOptions exportOptions,
  }) => [
    '-hide_banner',
    '-nostdin',
    '-y',
    ...trim.toFfmpegInputPrefixArgs(),
    '-i',
    inputPath,
    '-map',
    '0:v:0',
    if (exportOptions.keepAudio) ...['-map', '0:a?'],
    if (exportOptions.stripMetadata) ...['-map_metadata', '-1'],
    '-vf',
    'lut3d=file=restore.cube:interp=tetrahedral',
    '-c:v',
    'libx264',
    '-preset',
    'medium',
    '-crf',
    '18',
    '-pix_fmt',
    'yuv420p',
    if (exportOptions.keepAudio) ...['-c:a', 'aac', '-b:a', '192k'] else '-an',
    ...trim.toFfmpegOutputArgs(),
    '-movflags',
    '+faststart',
    outputPath,
  ];

  Future<void> export({
    required String inputPath,
    required String outputPath,
    required ColorCube cube,
    required VideoEditSettings trim,
    required ExportOptions exportOptions,
    required void Function(Process process) onStarted,
  }) async {
    final workDir = await Directory.systemTemp.createTemp('aquarecover_lut');
    try {
      await cube.writeCube(p.join(workDir.path, 'restore.cube'));
      final process = await Process.start(
        ffmpeg,
        exportArguments(
          inputPath: p.absolute(inputPath),
          outputPath: p.absolute(outputPath),
          trim: trim,
          exportOptions: exportOptions,
        ),
        workingDirectory: workDir.path,
      );
      onStarted(process);
      final stdout = process.stdout.drain<void>();
      final stderr = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode;
      await stdout;
      if (exitCode != 0) {
        throw StateError(
          'Video restoration failed with FFmpeg exit $exitCode. '
          '${redactLog(await stderr, inputPath, outputPath)}',
        );
      }
    } finally {
      await workDir.delete(recursive: true);
    }
  }

  static String redactLog(String log, String inputPath, String outputPath) {
    final redacted = log
        .replaceAll(inputPath, p.basename(inputPath))
        .replaceAll(outputPath, p.basename(outputPath))
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
    if (redacted.isEmpty) return 'No FFmpeg log was returned.';
    return redacted.length > 2000
        ? '${redacted.substring(redacted.length - 2000)}...'
        : redacted;
  }
}
