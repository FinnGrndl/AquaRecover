import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../core/media/media_classifier.dart';
import '../core/models/media_kind.dart';

/// Restricts which files the MCP server may read and write.
///
/// With no roots every local path is allowed, which matches a command-line
/// tool started by the user. With roots, every path must resolve (following
/// symbolic links) inside one of them.
class PathPolicy {
  PathPolicy(Iterable<String> roots)
    : roots = [for (final root in roots) _canonical(p.absolute(root))];

  final List<String> roots;

  bool get isRestricted => roots.isNotEmpty;

  /// Returns the absolute, normalized form of [path] or throws when it lies
  /// outside the allowed roots. Paths that do not exist yet are checked via
  /// their closest existing parent.
  String check(String path) {
    if (path.trim().isEmpty) throw const FormatException('Path is empty.');
    final absolute = p.normalize(p.absolute(_expandHome(path)));
    if (!isRestricted) return absolute;
    final resolved = _canonical(absolute);
    for (final root in roots) {
      if (resolved == root || p.isWithin(root, resolved)) return absolute;
    }
    throw FileSystemException(
      'Path is outside the folders AquaRecover MCP may access '
      '(${roots.join(', ')}).',
      path,
    );
  }

  static String _expandHome(String path) {
    if (path != '~' && !path.startsWith('~/')) return path;
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null) return path;
    return path == '~' ? home : p.join(home, path.substring(2));
  }

  static String _canonical(String path) {
    var existing = path;
    final missing = <String>[];
    while (FileSystemEntity.typeSync(existing) ==
        FileSystemEntityType.notFound) {
      final parent = p.dirname(existing);
      if (parent == existing) break;
      missing.insert(0, p.basename(existing));
      existing = parent;
    }
    String resolved;
    try {
      resolved = Directory(existing).resolveSymbolicLinksSync();
    } on FileSystemException {
      resolved = existing;
    }
    return p.normalize(p.joinAll([resolved, ...missing]));
  }
}

/// Finds helper programs on the host: `ffmpeg`/`ffprobe` for video and, on
/// macOS, `sips` for HEIC and camera RAW stills.
class HostTools {
  HostTools() : ffmpeg = _find('ffmpeg'), ffprobe = _find('ffprobe');

  /// Pretends no helper programs are installed; used by tests.
  const HostTools.none() : ffmpeg = null, ffprobe = null;

  final String? ffmpeg;
  final String? ffprobe;

  bool get hasSips => Platform.isMacOS && File('/usr/bin/sips').existsSync();

  static String? _find(String name) {
    final executable = Platform.isWindows ? '$name.exe' : name;
    final candidates = <String>[
      for (final dir in (Platform.environment['PATH'] ?? '').split(
        Platform.isWindows ? ';' : ':',
      ))
        if (dir.isNotEmpty) p.join(dir, executable),
      if (!Platform.isWindows) ...[
        '/opt/homebrew/bin/$name',
        '/usr/local/bin/$name',
        '/usr/bin/$name',
      ],
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }
}

/// Decodes stills and video frames for the MCP tools.
class MediaDecoder {
  MediaDecoder(this.tools);

  final HostTools tools;

  static const maxEncodedBytes = 512 * 1024 * 1024;

  MediaKind kindOf(String path) {
    try {
      return MediaClassifier.classify(path);
    } on UnsupportedError {
      throw FormatException(
        'Unsupported file type ".${MediaClassifier.extensionOf(path)}". '
        'Supported: ${MediaClassifier.allExtensions.join(', ')}.',
      );
    }
  }

  /// Decodes a still. JPEG, PNG, WebP and TIFF decode in Dart; HEIC and camera
  /// RAW files are converted with macOS `sips` when available.
  Future<img.Image> decodeStill(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('File not found.', path);
    }
    if (await file.length() > maxEncodedBytes) {
      throw StateError('File is larger than 512 MB.');
    }
    final extension = MediaClassifier.extensionOf(path);
    final needsHost =
        MediaClassifier.platformDecodedImageExtensions.contains(extension) ||
        MediaClassifier.rawPhotoExtensions.contains(extension);
    final bytes = needsHost
        ? await _convertWithSips(path)
        : await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw FormatException('Could not decode ${p.basename(path)}.');
    }
    return img.bakeOrientation(decoded);
  }

  Future<Uint8List> _convertWithSips(String path) async {
    if (!tools.hasSips) {
      throw UnsupportedError(
        '.${MediaClassifier.extensionOf(path)} files need the platform decoder. '
        'The MCP server converts them with macOS sips; on this system convert '
        'to JPEG, PNG or TIFF first, or use the AquaRecover app.',
      );
    }
    final temp = await Directory.systemTemp.createTemp('aquarecover-mcp');
    try {
      final output = p.join(temp.path, 'decoded.png');
      final result = await Process.run('/usr/bin/sips', [
        '-s',
        'format',
        'png',
        path,
        '--out',
        output,
      ]);
      if (result.exitCode != 0 || !File(output).existsSync()) {
        throw StateError('sips could not convert ${p.basename(path)}.');
      }
      return await File(output).readAsBytes();
    } finally {
      await temp.delete(recursive: true);
    }
  }

  /// Extracts one video frame at [seconds] as an image using ffmpeg.
  Future<img.Image> decodeVideoFrame(String path, double seconds) async {
    final ffmpeg = requireFfmpeg();
    final result = await Process.run(ffmpeg, [
      '-hide_banner',
      '-loglevel',
      'error',
      '-ss',
      seconds.toStringAsFixed(3),
      '-i',
      path,
      '-frames:v',
      '1',
      '-f',
      'image2pipe',
      '-vcodec',
      'png',
      '-',
    ], stdoutEncoding: null);
    final bytes = result.stdout as List<int>;
    if (result.exitCode != 0 || bytes.isEmpty) {
      throw StateError(
        'ffmpeg could not read a frame at ${seconds.toStringAsFixed(2)} s: '
        '${(result.stderr as String).trim()}',
      );
    }
    final decoded = img.decodePng(Uint8List.fromList(bytes));
    if (decoded == null) throw const FormatException('Invalid video frame.');
    return decoded;
  }

  /// Returns the duration of a video in seconds, or null when unknown.
  Future<double?> videoDuration(String path) async {
    final ffprobe = tools.ffprobe;
    if (ffprobe == null) return null;
    final result = await Process.run(ffprobe, [
      '-v',
      'error',
      '-show_entries',
      'format=duration',
      '-of',
      'default=noprint_wrappers=1:nokey=1',
      path,
    ]);
    if (result.exitCode != 0) return null;
    return double.tryParse((result.stdout as String).trim());
  }

  String requireFfmpeg() {
    final ffmpeg = tools.ffmpeg;
    if (ffmpeg == null) {
      throw UnsupportedError(
        'Video tools need ffmpeg on PATH (for example `brew install ffmpeg` '
        'or `winget install ffmpeg`).',
      );
    }
    return ffmpeg;
  }
}
