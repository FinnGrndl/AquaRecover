import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/export_options.dart';
import '../models/lut_profile.dart';
import '../models/restoration_settings.dart';
import '../utils/output_paths.dart';
import 'lut_service.dart';
import 'underwater_processor.dart';

class ImageRestorationService {
  const ImageRestorationService({this.processor = const UnderwaterProcessor(), this.lutService = const LutService()});

  static const maxEncodedImageBytes = 512 * 1024 * 1024;
  final UnderwaterProcessor processor;
  final LutService lutService;

  Future<String> restoreFile(String inputPath, RestorationSettings settings, {ExportOptions exportOptions = const ExportOptions(), LutProfile lutProfile = LutProfile.none}) async {
    final inputFile = File(inputPath);
    if (!await inputFile.exists()) throw FileSystemException('Input image not found.', inputPath);
    final length = await inputFile.length();
    if (length > maxEncodedImageBytes) throw StateError('Input image is too large for local processing (${length ~/ (1024 * 1024)} MB).');
    final outputBytes = await restoreBytes(Uint8List.fromList(await inputFile.readAsBytes()), settings, exportOptions: exportOptions, lutProfile: lutProfile);
    final outputPath = await OutputPaths.forImage(inputPath, extension: exportOptions.imageFormat.extension);
    await File(outputPath).writeAsBytes(outputBytes, flush: true);
    return outputPath;
  }

  Future<Uint8List> restoreBytes(Uint8List inputBytes, RestorationSettings settings, {ExportOptions exportOptions = const ExportOptions(), LutProfile lutProfile = LutProfile.none}) async {
    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) throw const FormatException('Could not decode image bytes.');
    final restored = processor.restoreImage(decoded, settings);
    final withLut = await lutService.apply(restored, lutProfile);
    if (exportOptions.outputPng) return Uint8List.fromList(img.encodePng(withLut));
    return Uint8List.fromList(img.encodeJpg(withLut, quality: settings.jpegQuality.clamp(1, 100).toInt()));
  }
}
