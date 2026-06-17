import 'dart:io';

import 'package:flutter/services.dart';
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

    final outputBytes = await restoreBytes(
      Uint8List.fromList(await inputFile.readAsBytes()),
      settings,
      exportOptions: exportOptions,
      lutProfile: lutProfile,
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
    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) {
      throw const FormatException('Could not decode image bytes.');
    }
    final restored = processor.restoreImage(decoded, settings);
    final withLut = await lutService.apply(restored, lutProfile);
    if (exportOptions.outputPng) {
      return Uint8List.fromList(img.encodePng(withLut));
    }
    return Uint8List.fromList(
      img.encodeJpg(
        withLut,
        quality: settings.jpegQuality.clamp(1, 100).toInt(),
      ),
    );
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
