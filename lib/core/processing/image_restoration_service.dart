import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' hide Uint8List;
import 'package:image/image.dart' as img;

import '../media/capture_metadata.dart';
import '../models/export_options.dart';
import '../models/image_transform_settings.dart';
import '../models/lut_profile.dart';
import '../models/restoration_settings.dart';
import '../utils/output_paths.dart';
import 'export_metadata.dart';
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

  /// Restores the still at [inputPath] into a new export file.
  ///
  /// [metadataSourcePath] names the original file whose EXIF the export keeps
  /// (unless [ExportOptions.stripMetadata] is set) when [inputPath] is an
  /// intermediate decode of it, such as a RAW or HEIC converted to PNG.
  Future<String> restoreFile(
    String inputPath,
    RestorationSettings settings, {
    ExportOptions exportOptions = const ExportOptions(),
    LutProfile lutProfile = LutProfile.none,
    ImageTransformSettings transform = const ImageTransformSettings(),
    String? metadataSourcePath,
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
      beforeAfter: exportOptions.beforeAfter,
    );

    if (_canUseNativeRenderer) {
      try {
        if (exportOptions.beforeAfter) {
          return await _composeNativeBeforeAfter(
            inputPath,
            outputPath,
            settings,
            exportOptions: exportOptions,
            lutProfile: lutProfile,
            transform: transform,
            metadataSourcePath: metadataSourcePath,
          );
        }
        final restored = await _restoreFileNatively(
          inputPath,
          outputPath,
          settings,
          exportOptions: exportOptions,
          lutProfile: lutProfile,
          transform: transform,
        );
        if (!exportOptions.stripMetadata) {
          await compute(
            _embedSourceMetadataInBackground,
            (restored, metadataSourcePath ?? inputPath),
            debugLabel: 'AquaRecover export metadata',
          );
        }
        return restored;
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
        metadataSourcePath: metadataSourcePath,
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

  /// Renders the restored pane with the native pipeline into a lossless
  /// intermediate, then composes the comparison in the background: the
  /// "before" pane is the portable decode with the same transform.
  Future<String> _composeNativeBeforeAfter(
    String inputPath,
    String outputPath,
    RestorationSettings settings, {
    required ExportOptions exportOptions,
    required LutProfile lutProfile,
    required ImageTransformSettings transform,
    String? metadataSourcePath,
  }) async {
    var restoredPath = await OutputPaths.forIntermediatePng(
      inputPath,
      label: 'restored',
    );
    try {
      restoredPath = await _restoreFileNatively(
        inputPath,
        restoredPath,
        settings,
        exportOptions: exportOptions.copyWith(
          imageFormat: ImageOutputFormat.png,
          stripMetadata: true,
          beforeAfter: false,
        ),
        lutProfile: lutProfile,
        transform: transform,
      );
      final outputBytes = await compute(
        _composeBeforeAfterInBackground,
        _BeforeAfterComposeRequest(
          inputPath: inputPath,
          restoredPath: restoredPath,
          metadataSourcePath: metadataSourcePath ?? inputPath,
          settings: settings.toJson(),
          exportOptions: exportOptions.toJson(),
          transform: transform.toJson(),
        ),
        debugLabel: 'AquaRecover before/after',
      );
      await File(outputPath).writeAsBytes(outputBytes, flush: true);
      return outputPath;
    } finally {
      try {
        final restored = File(restoredPath);
        if (await restored.exists()) await restored.delete();
      } on FileSystemException {
        // Best effort: the intermediate lives in the temporary directory.
      }
    }
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
    required this.metadataSourcePath,
    required this.settings,
    required this.exportOptions,
    required this.lutProfile,
    required this.transform,
  });

  final String inputPath;
  final String? metadataSourcePath;
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
    this.sourceExif,
  });

  final Uint8List inputBytes;
  final Map<String, Object?> settings;
  final Map<String, Object?> exportOptions;
  final Map<String, Object?> lutProfile;
  final Map<String, Object?> transform;
  final img.ExifData? sourceExif;
}

class _BeforeAfterComposeRequest {
  const _BeforeAfterComposeRequest({
    required this.inputPath,
    required this.restoredPath,
    required this.metadataSourcePath,
    required this.settings,
    required this.exportOptions,
    required this.transform,
  });

  final String inputPath;
  final String restoredPath;
  final String metadataSourcePath;
  final Map<String, Object?> settings;
  final Map<String, Object?> exportOptions;
  final Map<String, Object?> transform;
}

Future<Uint8List> _composeBeforeAfterInBackground(
  _BeforeAfterComposeRequest request,
) async {
  const pipeline = StillRenderPipeline();
  final exportOptions = ExportOptions.fromJson(request.exportOptions);
  final source = pipeline.decode(await File(request.inputPath).readAsBytes());
  final restored = pipeline.decode(
    await File(request.restoredPath).readAsBytes(),
  );
  final composite = pipeline.composeBeforeAfter(
    source,
    restored,
    transform: ImageTransformSettings.fromJson(request.transform),
    exportOptions: exportOptions,
  );
  return pipeline.encodeExport(
    composite,
    exportOptions: exportOptions,
    jpegQuality: RestorationSettings.fromJson(request.settings).jpegQuality,
    sourceExif: exportOptions.stripMetadata
        ? null
        : await CaptureMetadata.exifFromFile(request.metadataSourcePath),
  );
}

Future<Uint8List> _restoreFileBytesInBackground(
  _ImageFileRestoreRequest request,
) async {
  final metadataSourcePath = request.metadataSourcePath;
  final keepMetadata = !ExportOptions.fromJson(
    request.exportOptions,
  ).stripMetadata;
  return _restoreBytesInBackground(
    _ImageBytesRestoreRequest(
      inputBytes: await File(request.inputPath).readAsBytes(),
      settings: request.settings,
      exportOptions: request.exportOptions,
      lutProfile: request.lutProfile,
      transform: request.transform,
      sourceExif:
          keepMetadata &&
              metadataSourcePath != null &&
              metadataSourcePath != request.inputPath
          ? await CaptureMetadata.exifFromFile(metadataSourcePath)
          : null,
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
    sourceExif: request.sourceExif,
  );
}

/// Copies the EXIF of `request.$2` into the natively rendered export at
/// `request.$1`, using the same rules as the portable pipeline.
Future<void> _embedSourceMetadataInBackground((String, String) request) async {
  final (outputPath, sourcePath) = request;
  try {
    final sourceExif = await CaptureMetadata.exifFromFile(sourcePath);
    if (sourceExif == null) return;
    final output = File(outputPath);
    final bytes = await output.readAsBytes();
    final info = img.findDecoderForData(bytes)?.startDecode(bytes);
    if (info == null) return;
    final exif = ExportMetadata.forExport(
      sourceExif,
      width: info.width,
      height: info.height,
    );
    if (exif == null) return;
    final embedded = ExportMetadata.embed(bytes, exif);
    if (identical(embedded, bytes)) return;
    await output.writeAsBytes(embedded, flush: true);
  } on Object {
    // Metadata is best effort: the rendered export stays valid without it.
  }
}
