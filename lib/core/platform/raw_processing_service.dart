import 'dart:io';

import 'package:flutter/services.dart';

import '../models/export_options.dart';
import '../models/image_transform_settings.dart';
import '../models/lut_profile.dart';
import '../models/restoration_settings.dart';
import '../processing/image_restoration_service.dart';
import '../utils/output_paths.dart';

class RawProcessingService {
  RawProcessingService({
    MethodChannel? channel,
    ImageRestorationService? imageService,
  }) : _channel = channel ?? const MethodChannel('aqua_recover/raw'),
       _imageService = imageService ?? const ImageRestorationService();

  final MethodChannel _channel;
  final ImageRestorationService _imageService;

  Future<String> decodeRawToPng(String inputPath) =>
      _decodeToPng(inputPath, method: 'decodeRawToPng');
  Future<String> decodePlatformImageToPng(String inputPath) =>
      _decodeToPng(inputPath, method: 'decodeImageToPng');

  Future<String> restoreRawImage(
    String inputPath,
    RestorationSettings settings, {
    ExportOptions exportOptions = const ExportOptions(),
    LutProfile lutProfile = LutProfile.none,
    ImageTransformSettings transform = const ImageTransformSettings(),
  }) async {
    final decodedPng = await decodeRawToPng(inputPath);
    try {
      return await _imageService.restoreFile(
        decodedPng,
        settings,
        exportOptions: exportOptions,
        lutProfile: lutProfile,
        transform: transform,
      );
    } finally {
      await _deleteIntermediate(decodedPng);
    }
  }

  Future<String> restorePlatformDecodedImage(
    String inputPath,
    RestorationSettings settings, {
    ExportOptions exportOptions = const ExportOptions(),
    LutProfile lutProfile = LutProfile.none,
    ImageTransformSettings transform = const ImageTransformSettings(),
  }) async {
    final decodedPng = await decodePlatformImageToPng(inputPath);
    try {
      return await _imageService.restoreFile(
        decodedPng,
        settings,
        exportOptions: exportOptions,
        lutProfile: lutProfile,
        transform: transform,
      );
    } finally {
      await _deleteIntermediate(decodedPng);
    }
  }

  Future<String> _decodeToPng(
    String inputPath, {
    required String method,
  }) async {
    final inputFile = File(inputPath);
    if (!await inputFile.exists()) {
      throw FileSystemException('Input media not found.', inputPath);
    }
    final outputPath = await OutputPaths.forIntermediatePng(inputPath);
    try {
      final result = await _channel.invokeMethod<String>(method, {
        'inputPath': inputPath,
        'outputPath': outputPath,
      });
      return result ?? outputPath;
    } on Object {
      await _deleteIntermediate(outputPath);
      rethrow;
    }
  }

  static Future<void> _deleteIntermediate(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } on Object {
      // Best-effort cleanup only; export success should not depend on temp deletion.
    }
  }
}
