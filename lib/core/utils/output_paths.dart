import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class OutputPaths {
  static final _unsafeStemCharacters = RegExp(r'[^A-Za-z0-9._ -]+');
  static final _emptyStemCharacters = RegExp(r'[._ -]');
  static final _edgeStemCharacters = RegExp(r'^[._ -]+|[._ -]+$');
  static final _safeExtensionPattern = RegExp(r'^[a-z0-9]{1,8}$');

  static Future<Directory> outputDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'AquaRecover Exports'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<String> forImage(String inputPath, {String extension = 'jpg'}) {
    return _forMedia(inputPath, extension: extension, suffix: 'aqua');
  }

  static Future<String> forVideo(String inputPath, {String extension = 'mp4'}) {
    return _forMedia(inputPath, extension: extension, suffix: 'aqua');
  }

  static Future<String> forIntermediatePng(String inputPath) async {
    final dir = await intermediateDirectory();
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final stem = _safeStem(inputPath);
    return p.join(dir.path, '${stem}_raw_decode_$stamp.png');
  }

  static Future<Directory> intermediateDirectory() async {
    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, 'AquaRecover Intermediates'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<String> _forMedia(
    String inputPath, {
    required String extension,
    required String suffix,
  }) async {
    final dir = await outputDirectory();
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final stem = _safeStem(inputPath);
    final safeExtension = _safeExtension(extension);
    return p.join(dir.path, '${stem}_${suffix}_$stamp.$safeExtension');
  }

  static String _safeStem(String inputPath) {
    final rawStem = p.basenameWithoutExtension(inputPath).trim();
    final sanitized = rawStem.replaceAll(_unsafeStemCharacters, '_').trim();
    final compact = sanitized
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(_edgeStemCharacters, '');
    final nonEmpty = compact.replaceAll(_emptyStemCharacters, '').isEmpty
        ? 'media'
        : compact;
    return nonEmpty.length > 80 ? nonEmpty.substring(0, 80) : nonEmpty;
  }

  static String _safeExtension(String extension) {
    final sanitized = extension.toLowerCase().replaceFirst(RegExp(r'^\.+'), '');
    if (!_safeExtensionPattern.hasMatch(sanitized)) {
      throw FormatException('Unsafe output extension: $extension');
    }
    return sanitized;
  }
}
