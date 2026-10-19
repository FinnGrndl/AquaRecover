import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' hide Uint8List;

import '../models/export_options.dart';
import '../models/image_transform_settings.dart';
import '../models/lut_profile.dart';
import '../models/restoration_settings.dart';
import '../utils/output_paths.dart';
import 'lut_service.dart';
import 'still_render_pipeline.dart';
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
    ImageTransformSettings transform = const ImageTransformSettings(),
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
      temporary: !exportOptions.keepLocalCopy,
    );

    if (_canUseNativeRenderer) {
      try {
        return await _restoreFileNatively(
          inputPath,
          outputPath,
          settings,
          exportOptions: exportOptions,
          lutProfile: lutProfile,
          transform: transform,
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
        transform: transform.toJson(),
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
    ImageTransformSettings transform = const ImageTransformSettings(),
  }) async {
    return compute(
      _restoreBytesInBackground,
      _ImageBytesRestoreRequest(
        inputBytes: inputBytes,
        settings: settings.toJson(),
        exportOptions: exportOptions.toJson(),
        lutProfile: lutProfile.toJson(),
        transform: transform.toJson(),
      ),
      debugLabel: 'AquaRecover image bytes',
    );
  }

  /// iOS and macOS render stills with the shared Core Image pipeline, which
  /// also decodes HEIC and applies custom `.cube` LUTs on the GPU.
  bool get _canUseNativeRenderer => Platform.isIOS || Platform.isMacOS;

  Future<String> _restoreFileNatively(
    String inputPath,
    String outputPath,
    RestorationSettings settings, {
    required ExportOptions exportOptions,
    required LutProfile lutProfile,
    required ImageTransformSettings transform,
  }) async {
    await File(outputPath).parent.create(recursive: true);
    final restored = await _nativeChannel.invokeMethod<String>('restoreImage', {
      'inputPath': inputPath,
      'outputPath': outputPath,
      'settings': settings.toJson(),
      'exportOptions': exportOptions.toJson(),
      'lutProfile': lutProfile.toJson(),
      'transform': transform.toJson(),
    });
    if (restored == null || restored.isEmpty) {
      throw StateError(
        'Native image restoration did not return an output path.',
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
    required this.transform,
  });

  final String inputPath;
  final Map<String, Object?> settings;
  final Map<String, Object?> exportOptions;
  final Map<String, Object?> lutProfile;
  final Map<String, Object?> transform;
}

class _ImageBytesRestoreRequest {
  const _ImageBytesRestoreRequest({
    required this.inputBytes,
    required this.settings,
    required this.exportOptions,
    required this.lutProfile,
    required this.transform,
  });

  final Uint8List inputBytes;
  final Map<String, Object?> settings;
  final Map<String, Object?> exportOptions;
  final Map<String, Object?> lutProfile;
  final Map<String, Object?> transform;
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
      transform: request.transform,
    ),
  );
}

Future<Uint8List> _restoreBytesInBackground(_ImageBytesRestoreRequest request) {
  return const StillRenderPipeline().renderEncoded(
    request.inputBytes,
    settings: RestorationSettings.fromJson(request.settings),
    exportOptions: ExportOptions.fromJson(request.exportOptions),
    lutProfile: LutProfile.fromJson(request.lutProfile),
    transform: ImageTransformSettings.fromJson(request.transform),
  );
}
