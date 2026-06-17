import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' hide Uint8List;
import 'package:image/image.dart' as img;

import '../models/export_options.dart';
import '../models/lut_profile.dart';
import '../models/restoration_settings.dart';
import '../utils/output_paths.dart';
import 'lut_service.dart';
import 'underwater_processor.dart';

class ImageRestorationService {
  const ImageRestorationService({
    this.processor = const UnderwaterProcessor(),
    this.lutService = const LutService(),
    MethodChannel nativeChannel = const MethodChannel('aqua_recover/image'),
  }) : _nativeChannel = nativeChannel;

  static const maxEncodedImageBytes = 512 * 1024 * 1024;
  static const maxDecodedImagePixels = 120 * 1000 * 1000;
  static const maxDecodedImageDimension = 16384;
  final UnderwaterProcessor processor;
  final LutService lutService;
  final MethodChannel _nativeChannel;

  Future<String> restoreFile(
    String inputPath,
    RestorationSettings settings, {
    ExportOptions exportOptions = const ExportOptions(),
    LutProfile lutProfile = LutProfile.none,
  }) async {
    final inputFile = File(inputPath);
    if (!await inputFile.exists()) {
      throw FileSystemException('Input image not found.', inputPath);
    }
    final length = await inputFile.length();
    if (length > maxEncodedImageBytes) {
      throw StateError(
        'Input image is too large for local processing (${length ~/ (1024 * 1024)} MB).',
      );
    }
    final outputPath = await OutputPaths.forImage(
      inputPath,
      extension: exportOptions.imageFormat.extension,
    );

    if (_canUseNativeIos(lutProfile)) {
      try {
        return await _restoreFileOnIos(
          inputPath,
          outputPath,
          settings,
          exportOptions: exportOptions,
          lutProfile: lutProfile,
        );
      } on MissingPluginException {
        // Fall through to the portable Dart renderer for tests and non-runner builds.
      } on PlatformException catch (error) {
        if (_isNativeSafetyLimit(error)) rethrow;
      }
    }

    final outputBytes = await compute(
      _restoreFileBytesInBackground,
      _ImageFileRestoreRequest(
        inputPath: inputPath,
        settings: settings.toJson(),
        exportOptions: exportOptions.toJson(),
        lutProfile: lutProfile.toJson(),
      ),
      debugLabel: 'AquaRecover image export',
    );
    await File(outputPath).writeAsBytes(outputBytes, flush: true);
    return outputPath;
  }

  Future<Uint8List> restoreBytes(
    Uint8List inputBytes,
    RestorationSettings settings, {
    ExportOptions exportOptions = const ExportOptions(),
    LutProfile lutProfile = LutProfile.none,
  }) async {
    return compute(
      _restoreBytesInBackground,
      _ImageBytesRestoreRequest(
        inputBytes: inputBytes,
        settings: settings.toJson(),
        exportOptions: exportOptions.toJson(),
        lutProfile: lutProfile.toJson(),
      ),
      debugLabel: 'AquaRecover image bytes',
    );
  }

  static void _validateDecodedImage(img.Image decoded) {
    if (decoded.width <= 0 || decoded.height <= 0) {
      throw const FormatException('Decoded image dimensions are invalid.');
    }
    if (decoded.width > maxDecodedImageDimension ||
        decoded.height > maxDecodedImageDimension ||
        decoded.width * decoded.height > maxDecodedImagePixels) {
      throw StateError(
        'Decoded image is too large for local processing '
        '(${decoded.width}x${decoded.height}).',
      );
    }
  }

  bool _canUseNativeIos(LutProfile lutProfile) =>
      Platform.isIOS && !lutProfile.isCustomCube;

  Future<String> _restoreFileOnIos(
    String inputPath,
    String outputPath,
    RestorationSettings settings, {
    required ExportOptions exportOptions,
    required LutProfile lutProfile,
  }) async {
    await File(outputPath).parent.create(recursive: true);
    final restored = await _nativeChannel.invokeMethod<String>('restoreImage', {
      'inputPath': inputPath,
      'outputPath': outputPath,
      'settings': settings.toJson(),
      'exportOptions': exportOptions.toJson(),
      'lutProfile': lutProfile.toJson(),
    });
    if (restored == null || restored.isEmpty) {
      throw StateError(
        'Native iOS image restoration did not return an output path.',
      );
    }
    return restored;
  }

  bool _isNativeSafetyLimit(PlatformException error) {
    final text = '${error.code} ${error.message ?? ''}'.toLowerCase();
    return text.contains('too large') ||
        text.contains('safe limit') ||
        text.contains('dimensions exceed');
  }
}

class _ImageFileRestoreRequest {
  const _ImageFileRestoreRequest({
    required this.inputPath,
    required this.settings,
    required this.exportOptions,
    required this.lutProfile,
  });

  final String inputPath;
  final Map<String, Object?> settings;
  final Map<String, Object?> exportOptions;
  final Map<String, Object?> lutProfile;
}

class _ImageBytesRestoreRequest {
  const _ImageBytesRestoreRequest({
    required this.inputBytes,
    required this.settings,
    required this.exportOptions,
    required this.lutProfile,
  });

  final Uint8List inputBytes;
  final Map<String, Object?> settings;
  final Map<String, Object?> exportOptions;
  final Map<String, Object?> lutProfile;
}

Future<Uint8List> _restoreFileBytesInBackground(
  _ImageFileRestoreRequest request,
) async {
  return _restoreBytesInBackground(
    _ImageBytesRestoreRequest(
      inputBytes: await File(request.inputPath).readAsBytes(),
      settings: request.settings,
      exportOptions: request.exportOptions,
      lutProfile: request.lutProfile,
    ),
  );
}

Future<Uint8List> _restoreBytesInBackground(
  _ImageBytesRestoreRequest request,
) async {
  final decoded = img.decodeImage(request.inputBytes);
  if (decoded == null) {
    throw const FormatException('Could not decode image bytes.');
  }
  ImageRestorationService._validateDecodedImage(decoded);
  final settings = _settingsFromJson(request.settings);
  final exportOptions = _exportOptionsFromJson(request.exportOptions);
  final lutProfile = _lutProfileFromJson(request.lutProfile);
  final restored = const UnderwaterProcessor().restoreImage(decoded, settings);
  final withLut = await const LutService().apply(restored, lutProfile);
  if (exportOptions.outputPng) {
    return Uint8List.fromList(img.encodePng(withLut));
  }
  return Uint8List.fromList(
    img.encodeJpg(withLut, quality: settings.jpegQuality.clamp(1, 100).toInt()),
  );
}

RestorationSettings _settingsFromJson(Map<String, Object?> map) {
  double d(String key, double fallback) =>
      (map[key] as num?)?.toDouble() ?? fallback;
  int i(String key, int fallback) => (map[key] as num?)?.toInt() ?? fallback;
  final presetName = map['preset'] as String?;
  final preset = RestorationPreset.values.firstWhere(
    (value) => value.name == presetName,
    orElse: () => RestorationPreset.auto,
  );
  return RestorationSettings(
    preset: preset,
    recovery: d('recovery', 1.18),
    redRecovery: d('redRecovery', 1.24),
    autoWhiteBalance: d('autoWhiteBalance', 0.76),
    contrastStretch: d('contrastStretch', 0.58),
    contrast: d('contrast', 1.04),
    gamma: d('gamma', 0.98),
    saturation: d('saturation', 0.88),
    vibrance: d('vibrance', 0.06),
    clarity: d('clarity', 0.18),
    sharpness: d('sharpness', 0.18),
    hazeReduction: d('hazeReduction', 0.14),
    highlightProtection: d('highlightProtection', 0.55),
    hue: d('hue', 0),
    brightness: d('brightness', 0),
    exposure: d('exposure', -0.04),
    highlights: d('highlights', 0),
    shadows: d('shadows', 0),
    blackPoint: d('blackPoint', 0),
    vignette: d('vignette', 0),
    jpegQuality: i('jpegQuality', 94),
  );
}

ExportOptions _exportOptionsFromJson(Map<String, Object?> map) {
  final formatName = map['imageFormat'] as String?;
  final format = ImageOutputFormat.values.firstWhere(
    (value) => value.name == formatName,
    orElse: () => ImageOutputFormat.jpeg,
  );
  return ExportOptions(
    imageFormat: format,
    stripMetadata: map['stripMetadata'] as bool? ?? true,
    saveToPhotoLibrary: map['saveToPhotoLibrary'] as bool? ?? false,
    keepAudio: map['keepAudio'] as bool? ?? true,
  );
}

LutProfile _lutProfileFromJson(Map<String, Object?> map) {
  final kindName = map['kind'] as String?;
  final kind = LutKind.values.firstWhere(
    (value) => value.name == kindName,
    orElse: () => LutKind.none,
  );
  return LutProfile(
    kind: kind,
    name: map['name'] as String? ?? 'None',
    path: map['path'] as String?,
    intensity: (map['intensity'] as num?)?.toDouble() ?? 0,
  );
}
