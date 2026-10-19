import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/media_kind.dart';
import 'scene_analyzer.dart';

/// Decoded 8-bit RGBA pixels of a small version of a photo.
typedef RgbaThumbnail = ({Uint8List rgba, int width, int height});

/// Decodes [path] to a thumbnail no larger than [maxDimension] on its long
/// side, or returns null when the format cannot be decoded.
typedef ThumbnailDecoder =
    Future<RgbaThumbnail?> Function(String path, int maxDimension);

/// Suggests a starting preset for a photo, so the editor can offer "this
/// looks like green water" before the user tries presets one by one.
///
/// Uses the engine's image decoder at thumbnail size, which reads HEIC on
/// Apple platforms and costs a few milliseconds per photo. Results are cached
/// per file version.
class SceneSuggestionService {
  SceneSuggestionService({
    ThumbnailDecoder? decoder,
    this.analyzer = const SceneAnalyzer(),
    this.maxDimension = 320,
    this.capacity = 64,
  }) : _decoder = decoder ?? decodeWithEngine;

  final ThumbnailDecoder _decoder;
  final SceneAnalyzer analyzer;
  final int maxDimension;
  final int capacity;
  final _cache = <String, SceneAnalysis?>{};

  /// Whether [kind] can get a suggestion. RAW and video sources are left out
  /// because their thumbnails do not show the developed colours.
  static bool supports(MediaKind kind) => kind == MediaKind.photo;

  /// Returns null when [kind] is unsupported or the file cannot be read.
  Future<SceneAnalysis?> suggest(String path, MediaKind kind) async {
    if (!supports(kind)) return null;
    final String key;
    try {
      final stat = await File(path).stat();
      if (stat.type == FileSystemEntityType.notFound) return null;
      key = '$path|${stat.size}|${stat.modified.microsecondsSinceEpoch}';
    } on FileSystemException {
      return null;
    }
    if (_cache.containsKey(key)) {
      final cached = _cache.remove(key);
      _cache[key] = cached;
      return cached;
    }
    SceneAnalysis? analysis;
    try {
      final thumbnail = await _decoder(path, maxDimension);
      if (thumbnail != null) {
        analysis = analyzer.analyzeRgba(
          thumbnail.rgba,
          thumbnail.width,
          thumbnail.height,
        );
      }
    } on Object {
      analysis = null;
    }
    _cache[key] = analysis;
    while (_cache.length > capacity) {
      _cache.remove(_cache.keys.first);
    }
    return analysis;
  }

  static Future<RgbaThumbnail?> decodeWithEngine(
    String path,
    int maxDimension,
  ) async {
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    final ui.Codec codec;
    try {
      // The codec takes ownership of the buffer once it exists.
      codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (width, height) {
          final longSide = math.max(width, height);
          if (longSide <= maxDimension) {
            return ui.TargetImageSize(width: width, height: height);
          }
          final scale = maxDimension / longSide;
          return ui.TargetImageSize(
            width: math.max(1, (width * scale).round()),
            height: math.max(1, (height * scale).round()),
          );
        },
      );
    } on Object {
      buffer.dispose();
      rethrow;
    }
    ui.Image? image;
    try {
      image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      return (
        rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        width: image.width,
        height: image.height,
      );
    } finally {
      image?.dispose();
      codec.dispose();
    }
  }
}
