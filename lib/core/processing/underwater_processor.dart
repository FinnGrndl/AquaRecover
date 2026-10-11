import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/restoration_settings.dart';

enum RestorationRenderQuality { export, preview }

extension on RestorationRenderQuality {
  int get fusionGuideDimension => switch (this) {
    RestorationRenderQuality.export => 420,
    RestorationRenderQuality.preview => 180,
  };

  double get detailScale => switch (this) {
    RestorationRenderQuality.export => 1.0,
    RestorationRenderQuality.preview => 0.0,
  };
}

class UnderwaterProcessor {
  const UnderwaterProcessor();
  static const maxDimension = 16384;
  static const maxPixels = 120000000;

  Uint8List restoreEncodedImage(
    Uint8List bytes,
    RestorationSettings settings, {
    bool outputPng = false,
  }) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Could not decode image bytes.');
    }
    final restored = restoreImage(decoded, settings);
    if (outputPng) return Uint8List.fromList(img.encodePng(restored));
    return Uint8List.fromList(
      img.encodeJpg(
        restored,
        quality: settings.jpegQuality.clamp(1, 100).toInt(),
      ),
    );
  }

  img.Image restoreImage(
    img.Image source,
    RestorationSettings settings, {
    RestorationRenderQuality quality = RestorationRenderQuality.export,
  }) {
    _validateImageSize(source);
    if (settings.isIdentity) return source.clone();
    final src = _Rgba8.of(source);
    final width = src.width;
    final height = src.height;
    final stats = _ImageStats.from(src);
    final output = img.Image(width: width, height: height, numChannels: 4);
    final out = output.data!.toUint8List();
    final plan = _CorrectionPlan.from(settings, stats, width, height);
    plan.correctRows(src.bytes, 0, out, 0, 0, height);
    final fused = _retinexFusion(src, output, stats, settings, quality);
    return _applyDetail(fused, settings, quality);
  }

  /// Same result as [restoreImage], computed in horizontal bands on worker
  /// isolates. Large exports scale with the available CPU cores; small images
  /// and single-core devices fall back to the synchronous path.
  Future<img.Image> restoreImageInParallel(
    img.Image source,
    RestorationSettings settings, {
    RestorationRenderQuality quality = RestorationRenderQuality.export,
    int? workers,
  }) async {
    _validateImageSize(source);
    final bandCount = parallelBandCount(
      source.width * source.height,
      processors: workers ?? Platform.numberOfProcessors,
    );
    if (settings.isIdentity || bandCount <= 1) {
      return restoreImage(source, settings, quality: quality);
    }
    final src = _Rgba8.of(source);
    final width = src.width;
    final height = src.height;
    final rowBytes = width * 4;
    final stats = _ImageStats.from(src);
    final bands = _bands(height, bandCount);

    final correctionPlan = _CorrectionPlan.from(settings, stats, width, height);
    final output = img.Image(width: width, height: height, numChannels: 4);
    final corrected = output.data!.toUint8List();
    await Future.wait([
      for (final band in bands)
        _correctBand(
          correctionPlan,
          TransferableTypedData.fromList([
            Uint8List.sublistView(
              src.bytes,
              math.max(0, band.$1 - 1) * rowBytes,
              band.$2 * rowBytes,
            ),
          ]),
          math.max(0, band.$1 - 1),
          band.$1,
          band.$2,
        ).then(
          (rows) =>
              corrected.setRange(band.$1 * rowBytes, band.$2 * rowBytes, rows),
        ),
    ]);

    if (width >= 8 && height >= 8) {
      final guide = _FusionGuide.from(
        output,
        maxGuideDimension: quality.fusionGuideDimension,
      );
      final guideX = guide.indexTable(width, guide.width);
      final guideY = guide.indexTable(height, guide.height);
      final fusionPlan = _FusionPlan.from(settings, stats, width);
      await Future.wait([
        for (final band in bands)
          _fuseBand(
            fusionPlan,
            TransferableTypedData.fromList([
              Uint8List.sublistView(
                src.bytes,
                band.$1 * rowBytes,
                band.$2 * rowBytes,
              ),
            ]),
            TransferableTypedData.fromList([
              Uint8List.sublistView(
                corrected,
                band.$1 * rowBytes,
                band.$2 * rowBytes,
              ),
            ]),
            guide,
            guideX,
            guideY,
            band.$1,
            band.$2,
          ).then(
            (rows) => corrected.setRange(
              band.$1 * rowBytes,
              band.$2 * rowBytes,
              rows,
            ),
          ),
      ]);
    }
    return _applyDetail(output, settings, quality);
  }

  /// How many bands [restoreImageInParallel] uses for [pixels] on a machine
  /// with [processors] cores. Below ~1.5 MP the isolate hand-off costs more
  /// than it saves.
  static int parallelBandCount(int pixels, {required int processors}) {
    if (pixels < 1500000 || processors <= 1) return 1;
    final byWork = (pixels / 1000000).ceil();
    return math.max(1, math.min(math.min(processors, 8), byWork));
  }

  static List<(int, int)> _bands(int height, int count) {
    final bands = <(int, int)>[];
    for (var i = 0; i < count; i++) {
      final start = height * i ~/ count;
      final end = height * (i + 1) ~/ count;
      if (end > start) bands.add((start, end));
    }
    return bands;
  }

  // These helpers keep each worker closure's captured state to its own
  // arguments, so only the band's rows are copied to the worker isolate.
  static Future<Uint8List> _correctBand(
    _CorrectionPlan plan,
    TransferableTypedData input,
    int sourceRow,
    int yStart,
    int yEnd,
  ) async {
    final result = await Isolate.run(() {
      final rows = input.materialize().asUint8List();
      final out = Uint8List((yEnd - yStart) * plan.width * 4);
      plan.correctRows(rows, sourceRow, out, yStart, yStart, yEnd);
      return TransferableTypedData.fromList([out]);
    }, debugName: 'AquaRecover correction band');
    return result.materialize().asUint8List();
  }

  static Future<Uint8List> _fuseBand(
    _FusionPlan plan,
    TransferableTypedData source,
    TransferableTypedData corrected,
    _FusionGuide guide,
    Int32List guideX,
    Int32List guideY,
    int yStart,
    int yEnd,
  ) async {
    final result = await Isolate.run(() {
      final src = source.materialize().asUint8List();
      final dst = corrected.materialize().asUint8List();
      plan.fuseRows(
        src,
        yStart,
        dst,
        yStart,
        guide,
        guideX,
        guideY,
        yStart,
        yEnd,
      );
      return TransferableTypedData.fromList([dst]);
    }, debugName: 'AquaRecover fusion band');
    return result.materialize().asUint8List();
  }

  static img.Image _applyDetail(
    img.Image image,
    RestorationSettings settings,
    RestorationRenderQuality quality,
  ) {
    final detail =
        _clampD(settings.sharpness + settings.clarity * 0.75, 0.0, 1.2) *
        quality.detailScale;
    return detail <= 0.001 ? image : _unsharp3x3(image, detail);
  }

  static void _validateImageSize(img.Image image) {
    if (image.width <= 0 || image.height <= 0) {
      throw const FormatException('Image dimensions are invalid.');
    }
    if (image.width > maxDimension || image.height > maxDimension) {
      throw FormatException(
        'Images must be at most ${maxDimension}x$maxDimension.',
      );
    }
    if (image.width * image.height > maxPixels) {
      throw FormatException(
        'Image is too large. Maximum is $maxPixels pixels.',
      );
    }
  }

  static img.Image _unsharp3x3(img.Image source, double amount) {
    if (source.width < 3 || source.height < 3) return source;
    final sourceData = source.data;
    if (source.format == img.Format.uint8 &&
        sourceData != null &&
        source.numChannels >= 3) {
      final out = source.clone();
      final outData = out.data;
      if (outData != null &&
          outData.lengthInBytes == sourceData.lengthInBytes) {
        final src = sourceData.toUint8List();
        final dst = outData.toUint8List();
        final channels = source.numChannels;
        final stride = sourceData.rowStride;
        for (var y = 1; y < source.height - 1; y++) {
          final row = y * stride;
          final prevRow = row - stride;
          final nextRow = row + stride;
          for (var x = 1; x < source.width - 1; x++) {
            final index = row + x * channels;
            final left = index - channels;
            final right = index + channels;
            final top = prevRow + x * channels;
            final bottom = nextRow + x * channels;
            final topLeft = top - channels;
            final topRight = top + channels;
            final bottomLeft = bottom - channels;
            final bottomRight = bottom + channels;
            for (var channel = 0; channel < 3; channel++) {
              final i = index + channel;
              final sum =
                  src[topLeft + channel] +
                  src[top + channel] +
                  src[topRight + channel] +
                  src[left + channel] +
                  src[i] +
                  src[right + channel] +
                  src[bottomLeft + channel] +
                  src[bottom + channel] +
                  src[bottomRight + channel];
              dst[i] = _byte(src[i] + (src[i] - sum / 9.0) * amount);
            }
          }
        }
        return out;
      }
    }
    final out = source.clone();
    for (var y = 1; y < source.height - 1; y++) {
      for (var x = 1; x < source.width - 1; x++) {
        var sumR = 0.0, sumG = 0.0, sumB = 0.0;
        for (var yy = -1; yy <= 1; yy++) {
          for (var xx = -1; xx <= 1; xx++) {
            final p = source.getPixel(x + xx, y + yy);
            sumR += p.r.toDouble();
            sumG += p.g.toDouble();
            sumB += p.b.toDouble();
          }
        }
        final center = source.getPixel(x, y);
        out.setPixelRgba(
          x,
          y,
          _byte(center.r + (center.r - sumR / 9.0) * amount),
          _byte(center.g + (center.g - sumG / 9.0) * amount),
          _byte(center.b + (center.b - sumB / 9.0) * amount),
          center.a.toInt(),
        );
      }
    }
    return out;
  }

  /// The luminance-preserving hue rotation matrix, computed once per image.
  static Float64List _hueMatrix(double radians) {
    final cosA = math.cos(radians);
    final sinA = math.sin(radians);
    return Float64List.fromList([
      .213 + cosA * .787 - sinA * .213,
      .715 - cosA * .715 - sinA * .715,
      .072 - cosA * .072 + sinA * .928,
      .213 - cosA * .213 + sinA * .143,
      .715 + cosA * .285 + sinA * .140,
      .072 - cosA * .072 - sinA * .283,
      .213 - cosA * .213 - sinA * .787,
      .715 - cosA * .715 + sinA * .715,
      .072 + cosA * .928 + sinA * .072,
    ]);
  }

  static double _openWaterWeight(double r, double g, double b) {
    final blueGreen = math.max(g, b);
    if (blueGreen <= 1) return 0;
    final redDeficit = _clampD(((blueGreen - r) / 165.0), 0.0, 1.0);
    final blueDominance = _clampD(((b - r) / 180.0), 0.0, 1.0);
    final greenDominance = _clampD(((g - r) / 180.0), 0.0, 1.0);
    final chroma = _clampD(
      ((math.max(r, math.max(g, b)) - math.min(r, math.min(g, b))) / 140.0),
      0.0,
      1.0,
    );
    return _clampD(
      (redDeficit * (0.58 * blueDominance + 0.42 * greenDominance) * chroma),
      0.0,
      1.0,
    );
  }

  static double _recoverableCyanWeight(
    double r,
    double g,
    double b,
    double openWater,
  ) {
    final blueGreen = math.max(g, b);
    if (blueGreen <= 1) return 0;
    final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    final redDeficit = _clampD(((blueGreen - r) / 170.0), 0.0, 1.0);
    final brightSurface = _clampD(((luma - 42.0) / 132.0), 0.0, 1.0);
    final notPureWater = _clampD((1.0 - openWater * 0.52), 0.18, 1.0);
    return _clampD((redDeficit * brightSurface * notPureWater), 0.0, 1.0);
  }

  static double _localStructureWeight(
    Uint8List source,
    int width,
    int x,
    int y,
    double r,
    double g,
    double b,
  ) {
    if (width < 2 || source.length < width * 8) return 0;
    final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    var diff = 0.0;
    var samples = 0;
    if (x > 0) {
      diff += (luma - _bufferLuma(source, (y * width + x - 1) * 4)).abs();
      samples++;
    }
    if (y > 0) {
      diff += (luma - _bufferLuma(source, ((y - 1) * width + x) * 4)).abs();
      samples++;
    }
    if (samples == 0) return 0;
    return _clampD(((diff / samples - 4.0) / 34.0), 0.0, 1.0);
  }

  static double _bufferLuma(Uint8List data, int index) =>
      0.2126 * data[index] +
      0.7152 * data[index + 1] +
      0.0722 * data[index + 2];

  static img.Image _retinexFusion(
    _Rgba8 source,
    img.Image corrected,
    _ImageStats stats,
    RestorationSettings settings,
    RestorationRenderQuality quality,
  ) {
    if (corrected.width < 8 || corrected.height < 8) return corrected;
    final guide = _FusionGuide.from(
      corrected,
      maxGuideDimension: quality.fusionGuideDimension,
    );
    // Each pixel only reads its own corrected value, so the fusion can update
    // the corrected buffer in place instead of cloning it.
    final out = corrected;
    final dst = corrected.data!.toUint8List();
    final src = source.bytes;
    final width = corrected.width;
    final height = corrected.height;
    final guideX = guide.indexTable(width, guide.width);
    final guideY = guide.indexTable(height, guide.height);
    final plan = _FusionPlan.from(settings, stats, width);
    plan.fuseRows(src, 0, dst, 0, guide, guideX, guideY, 0, height);
    return out;
  }

  static double _mix(double a, double b, double t) =>
      a + (b - a) * (t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t));
  static double _stretch(double v, int low, int high) =>
      high <= low ? v : _clampD(((v - low) * 255.0 / (high - low)), 0.0, 255.0);
  static double _unit(double v) => _clampD((v / 255.0), 0.0, 1.0);
  static int _byte(double v) {
    final rounded = v.round();
    return rounded < 0 ? 0 : (rounded > 255 ? 255 : rounded);
  }
}

/// A double-only clamp; `num.clamp` is noticeably slower in hot loops.
double _clampD(double value, double lower, double upper) =>
    value < lower ? lower : (value > upper ? upper : value);

class _FusionGuide {
  const _FusionGuide({
    required this.width,
    required this.height,
    required this.luma,
    required this.localR,
    required this.localG,
    required this.localB,
    required this.localContrast,
    required this.structure,
  });

  final int width;
  final int height;
  final Float64List luma;
  final Float64List localR;
  final Float64List localG;
  final Float64List localB;
  final Float64List localContrast;
  final Float64List structure;

  factory _FusionGuide.from(
    img.Image corrected, {
    required int maxGuideDimension,
  }) {
    final scale = math.min(
      1.0,
      maxGuideDimension / math.max(corrected.width, corrected.height),
    );
    final guideImage = scale < 1.0
        ? img.copyResize(
            corrected,
            width: math.max(1, (corrected.width * scale).round()),
            height: math.max(1, (corrected.height * scale).round()),
            interpolation: img.Interpolation.linear,
          )
        : corrected;
    final width = guideImage.width;
    final height = guideImage.height;
    final luma = Float64List(width * height);
    final red = Float64List(width * height);
    final green = Float64List(width * height);
    final blue = Float64List(width * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final p = guideImage.getPixel(x, y);
        final index = y * width + x;
        red[index] = p.r / 255.0;
        green[index] = p.g / 255.0;
        blue[index] = p.b / 255.0;
        luma[index] =
            0.2126 * red[index] + 0.7152 * green[index] + 0.0722 * blue[index];
      }
    }
    final smallRadius = math.max(1, math.min(width, height) ~/ 70);
    final mediumRadius = math.max(2, math.min(width, height) ~/ 36);
    final largeRadius = math.max(3, math.min(width, height) ~/ 18);
    final smallBlur = _boxBlur(luma, width, height, smallRadius);
    final mediumBlur = _boxBlur(luma, width, height, mediumRadius);
    final largeBlur = _boxBlur(luma, width, height, largeRadius);
    final localR = _boxBlur(red, width, height, largeRadius);
    final localG = _boxBlur(green, width, height, largeRadius);
    final localB = _boxBlur(blue, width, height, largeRadius);
    final localContrast = Float64List(width * height);
    final structure = Float64List(width * height);
    for (var i = 0; i < luma.length; i++) {
      final smallDetail = luma[i] - smallBlur[i];
      final mediumDetail = luma[i] - mediumBlur[i];
      final largeDetail = luma[i] - largeBlur[i];
      localContrast[i] = _clampD(
        (smallDetail * 0.12 + mediumDetail * 0.32 + largeDetail * 0.56),
        -0.45,
        0.45,
      );
      structure[i] = _clampD(
        (smallDetail.abs() * 5.5 + mediumDetail.abs() * 3.0),
        0.0,
        1.0,
      );
    }
    return _FusionGuide(
      width: width,
      height: height,
      luma: luma,
      localR: localR,
      localG: localG,
      localB: localB,
      localContrast: localContrast,
      structure: structure,
    );
  }

  /// Maps every source coordinate to its nearest guide coordinate once, so the
  /// per-pixel loop avoids a division and rounding per lookup.
  Int32List indexTable(int sourceLength, int guideLength) {
    final table = Int32List(sourceLength);
    if (sourceLength <= 1) return table;
    for (var i = 0; i < sourceLength; i++) {
      table[i] = (i * (guideLength - 1) / (sourceLength - 1)).round().clamp(
        0,
        guideLength - 1,
      );
    }
    return table;
  }

  static Float64List _boxBlur(
    Float64List input,
    int width,
    int height,
    int radius,
  ) {
    if (radius <= 0) return Float64List.fromList(input);
    final horizontal = Float64List(input.length);
    final output = Float64List(input.length);
    final diameter = radius * 2 + 1;
    for (var y = 0; y < height; y++) {
      var sum = 0.0;
      for (var x = -radius; x <= radius; x++) {
        final xx = x.clamp(0, width - 1);
        sum += input[y * width + xx];
      }
      for (var x = 0; x < width; x++) {
        horizontal[y * width + x] = sum / diameter;
        final removeX = (x - radius).clamp(0, width - 1);
        final addX = (x + radius + 1).clamp(0, width - 1);
        sum += input[y * width + addX] - input[y * width + removeX];
      }
    }
    for (var x = 0; x < width; x++) {
      var sum = 0.0;
      for (var y = -radius; y <= radius; y++) {
        final yy = y.clamp(0, height - 1);
        sum += horizontal[yy * width + x];
      }
      for (var y = 0; y < height; y++) {
        output[y * width + x] = sum / diameter;
        final removeY = (y - radius).clamp(0, height - 1);
        final addY = (y + radius + 1).clamp(0, height - 1);
        sum += horizontal[addY * width + x] - horizontal[removeY * width + x];
      }
    }
    return output;
  }
}

class _ImageStats {
  const _ImageStats({
    required this.meanR,
    required this.meanG,
    required this.meanB,
    required this.lowR,
    required this.lowG,
    required this.lowB,
    required this.lowLuma,
    required this.lowMidLuma,
    required this.highR,
    required this.highG,
    required this.highB,
    required this.highLuma,
  });
  final double meanR, meanG, meanB;
  final int lowR,
      lowG,
      lowB,
      lowLuma,
      lowMidLuma,
      highR,
      highG,
      highB,
      highLuma;

  factory _ImageStats.from(_Rgba8 image) {
    final data = image.bytes;
    final histR = List<int>.filled(256, 0),
        histG = List<int>.filled(256, 0),
        histB = List<int>.filled(256, 0),
        histLuma = List<int>.filled(256, 0);
    final pixelCount = image.width * image.height;
    final stride = math.max(1, math.sqrt(pixelCount / 60000.0).floor());
    var count = 0;
    var sumR = 0.0, sumG = 0.0, sumB = 0.0;
    for (var y = 0; y < image.height; y += stride) {
      for (var x = 0; x < image.width; x += stride) {
        final index = (y * image.width + x) * 4;
        final r = data[index], g = data[index + 1], b = data[index + 2];
        final luma = (0.2126 * r + 0.7152 * g + 0.0722 * b)
            .round()
            .clamp(0, 255)
            .toInt();
        histR[r]++;
        histG[g]++;
        histB[b]++;
        histLuma[luma]++;
        sumR += r;
        sumG += g;
        sumB += b;
        count++;
      }
    }
    return _ImageStats(
      meanR: sumR / math.max(1, count),
      meanG: sumG / math.max(1, count),
      meanB: sumB / math.max(1, count),
      lowR: _percentile(histR, count, .01),
      lowG: _percentile(histG, count, .01),
      lowB: _percentile(histB, count, .01),
      lowLuma: _percentile(histLuma, count, .01),
      lowMidLuma: _percentile(histLuma, count, .10),
      highR: _percentile(histR, count, .995),
      highG: _percentile(histG, count, .995),
      highB: _percentile(histB, count, .995),
      highLuma: _percentile(histLuma, count, .995),
    );
  }

  static int _percentile(List<int> hist, int total, double p) {
    final target = math.max(1, (total * p).round().clamp(0, total)).toInt();
    var running = 0;
    for (var i = 0; i < hist.length; i++) {
      running += hist[i];
      if (running >= target) return i;
    }
    return hist.length - 1;
  }
}

/// A tightly packed 8-bit RGBA view of an image.
///
/// The restoration loops index this buffer directly instead of allocating a
/// `Pixel` per read. Images in other formats (16-bit, float, palette, or
/// without alpha) are converted first so their channel values are always on
/// the 0–255 scale the algorithm expects.
class _Rgba8 {
  const _Rgba8(this.width, this.height, this.bytes);

  factory _Rgba8.of(img.Image image) {
    final data = image.data;
    if (image.format == img.Format.uint8 &&
        image.numChannels == 4 &&
        !image.hasPalette &&
        data != null &&
        data.rowStride == image.width * 4) {
      return _Rgba8(image.width, image.height, data.toUint8List());
    }
    if (image.format == img.Format.uint8 &&
        image.numChannels == 3 &&
        !image.hasPalette &&
        data != null) {
      // JPEG decodes land here; expanding manually is much faster than the
      // generic per-pixel conversion.
      final source = data.toUint8List();
      final stride = data.rowStride;
      final rgba = Uint8List(image.width * image.height * 4);
      var out = 0;
      for (var y = 0; y < image.height; y++) {
        var index = y * stride;
        for (var x = 0; x < image.width; x++) {
          rgba[out] = source[index];
          rgba[out + 1] = source[index + 1];
          rgba[out + 2] = source[index + 2];
          rgba[out + 3] = 255;
          out += 4;
          index += 3;
        }
      }
      return _Rgba8(image.width, image.height, rgba);
    }
    final converted = image.convert(
      format: img.Format.uint8,
      numChannels: 4,
      alpha: 255,
    );
    return _Rgba8(
      converted.width,
      converted.height,
      converted.data!.toUint8List(),
    );
  }

  final int width;
  final int height;
  final Uint8List bytes;
}

/// Evaluates `pow(x, exponent)` on a bounded domain through a dense lookup
/// table with linear interpolation. The exponent is constant for an image, so
/// the table replaces millions of `math.pow` calls with two array reads.
///
/// Values close to the lower bound of a [_PowerCurve.new] curve, where a
/// fractional exponent is steep, still use `math.pow` to keep shadows exact.
class _PowerCurve {
  _PowerCurve(this.exponent)
    : min = 0,
      max = 1,
      _table = _build(exponent, 0, 1);

  _PowerCurve.range(this.exponent, this.min, this.max)
    : _table = _build(exponent, min, max);

  static const _segments = 4096;
  static const _exactBelow = 32 / _segments;

  final double exponent;
  final double min;
  final double max;
  final Float64List _table;

  static Float64List _build(double exponent, double min, double max) {
    final table = Float64List(_segments + 1);
    final step = (max - min) / _segments;
    for (var i = 0; i <= _segments; i++) {
      table[i] = math.pow(min + step * i, exponent).toDouble();
    }
    return table;
  }

  /// Returns `pow(value.clamp(min, max), exponent)`.
  double apply(double value) {
    if (exponent == 1.0) return value.clamp(min, max).toDouble();
    if (value <= min) return _table[0];
    if (value >= max) return _table[_segments];
    final position = (value - min) / (max - min);
    if (min == 0 && position < _exactBelow) {
      return math.pow(value, exponent).toDouble();
    }
    final scaled = position * _segments;
    final index = scaled.floor();
    final fraction = scaled - index;
    final low = _table[index];
    return low + (_table[index + 1] - low) * fraction;
  }
}

/// Every scene- and settings-derived constant of the global correction pass.
///
/// The plan is computed once per image and is sendable to worker isolates, so
/// independent row bands can be corrected in parallel.
class _CorrectionPlan {
  _CorrectionPlan({
    required this.width,
    required this.height,
    required this.lowLuma,
    required this.highLuma,
    required this.grayMean,
    required this.rGain,
    required this.gGain,
    required this.severeGlobalRedLoss,
    required this.blueNotDominant,
    required this.bGain,
    required this.recovery,
    required this.correctionScale,
    required this.redRecovery,
    required this.requestedContrastStretch,
    required this.sat,
    required this.vibrance,
    required this.contrast,
    required this.hazeReduction,
    required this.highlightProtection,
    required this.invGamma,
    required this.gammaCurve,
    required this.hueShift,
    required this.hue,
    required this.brightnessOffset,
    required this.exposureGain,
    required this.highlightAdjust,
    required this.shadowAdjust,
    required this.blackOffset,
    required this.vignette,
    required this.redGreenRatio,
    required this.blueGreenRatio,
    required this.deepBlueContrast,
    required this.contrastStretch,
    required this.darkBlueSceneLift,
    required this.shallowCyanHighlightLift,
    required this.shallowCyanWaterLift,
    required this.brightShallowCyanDim,
    required this.centerX,
    required this.centerY,
    required this.maxRadius,
  });

  factory _CorrectionPlan.from(
    RestorationSettings settings,
    _ImageStats stats,
    int width,
    int height,
  ) {
    final grayMean = (stats.meanR + stats.meanG + stats.meanB) / 3.0;
    final rGain = UnderwaterProcessor._mix(
      1.0,
      _clampD((grayMean / math.max(1.0, stats.meanR)), 0.75, 2.05),
      settings.autoWhiteBalance,
    );
    final gGain = UnderwaterProcessor._mix(
      1.0,
      _clampD((grayMean / math.max(1.0, stats.meanG)), 0.82, 1.28),
      settings.autoWhiteBalance * 0.45,
    );
    final severeGlobalRedLoss = stats.meanR / math.max(1.0, stats.meanG) < 0.12;
    final blueNotDominant =
        severeGlobalRedLoss && stats.meanB <= stats.meanG * 1.12;
    final bGain = UnderwaterProcessor._mix(
      1.0,
      (grayMean / math.max(1.0, stats.meanB))
          .clamp(blueNotDominant ? 0.90 : 0.58, 1.14)
          .toDouble(),
      settings.autoWhiteBalance * (blueNotDominant ? 0.26 : 0.62),
    );
    final recovery = _clampD(settings.recovery, 0.0, 1.5);
    final correctionScale = _clampD((recovery / 1.18), 0.0, 1.3);
    final redRecovery = _clampD(settings.redRecovery, 0.0, 2.5);
    final requestedContrastStretch = _clampD(
      settings.contrastStretch,
      0.0,
      1.0,
    );
    final sat = _clampD(settings.saturation, 0.0, 3.0);
    final vibrance = _clampD(settings.vibrance, 0.0, 1.0);
    final contrast = _clampD(settings.contrast, 0.1, 3.0);
    final hazeReduction = _clampD(settings.hazeReduction, 0.0, 1.0);
    final highlightProtection = _clampD(settings.highlightProtection, 0.0, 1.0);
    final invGamma = 1.0 / _clampD(settings.gamma, 0.1, 3.0);
    final gammaCurve = _PowerCurve(invGamma);
    final hueShift = _clampD(settings.hue, -1.0, 1.0) * math.pi;
    final hue = hueShift.abs() > 0.0001
        ? UnderwaterProcessor._hueMatrix(hueShift)
        : null;
    final brightnessOffset = _clampD(settings.brightness, -1.0, 1.0) * 70.0;
    final exposureGain = math
        .pow(2.0, _clampD(settings.exposure, -1.0, 1.0))
        .toDouble();
    final highlightAdjust = _clampD(settings.highlights, -1.0, 1.0) * 90.0;
    final shadowAdjust = _clampD(settings.shadows, -1.0, 1.0) * 90.0;
    final blackOffset = _clampD(settings.blackPoint, 0.0, 1.0) * 120.0;
    final vignette = _clampD(settings.vignette, 0.0, 1.0);
    final redGreenRatio = stats.meanR / math.max(1.0, stats.meanG);
    final blueGreenRatio = stats.meanB / math.max(1.0, stats.meanG);
    final deepBlueContrast = _clampD(
      ((blueGreenRatio - 1.20) / 0.18),
      0.0,
      1.0,
    );
    final contrastStretch = UnderwaterProcessor._mix(
      requestedContrastStretch,
      math.min(1.0, requestedContrastStretch + 0.06),
      deepBlueContrast,
    );
    final darkBlueSceneLift =
        (_clampD(((55.0 - stats.lowMidLuma) / 30.0), 0.0, 1.0) *
                _clampD(((blueGreenRatio - 1.25) / 0.20), 0.0, 1.0) *
                _clampD(((0.14 - redGreenRatio) / 0.14), 0.0, 1.0) *
                correctionScale)
            .toDouble();
    final shallowCyanHighlightLift = blueNotDominant
        ? severeGlobalRedLoss && stats.lowMidLuma < 82
        : false;
    final shallowCyanWaterLift =
        blueNotDominant && severeGlobalRedLoss && stats.lowMidLuma < 82
        ? (_clampD(((82.0 - stats.lowMidLuma) / 30.0), 0.0, 1.0) *
                  _clampD(((1.20 - blueGreenRatio) / 0.25), 0.0, 1.0) *
                  correctionScale)
              .toDouble()
        : 0.0;
    final brightShallowCyanDim = blueNotDominant && severeGlobalRedLoss
        ? (_clampD(((stats.lowMidLuma - 76.0) / 36.0), 0.0, 1.0) *
                  _clampD(((1.20 - blueGreenRatio) / 0.25), 0.0, 1.0) *
                  correctionScale)
              .toDouble()
        : 0.0;
    final centerX = (width - 1) / 2.0;
    final centerY = (height - 1) / 2.0;
    final maxRadius = math.max(
      1.0,
      math.sqrt(centerX * centerX + centerY * centerY),
    );

    return _CorrectionPlan(
      width: width,
      height: height,
      lowLuma: stats.lowLuma,
      highLuma: stats.highLuma,
      grayMean: grayMean,
      rGain: rGain,
      gGain: gGain,
      severeGlobalRedLoss: severeGlobalRedLoss,
      blueNotDominant: blueNotDominant,
      bGain: bGain,
      recovery: recovery,
      correctionScale: correctionScale,
      redRecovery: redRecovery,
      requestedContrastStretch: requestedContrastStretch,
      sat: sat,
      vibrance: vibrance,
      contrast: contrast,
      hazeReduction: hazeReduction,
      highlightProtection: highlightProtection,
      invGamma: invGamma,
      gammaCurve: gammaCurve,
      hueShift: hueShift,
      hue: hue,
      brightnessOffset: brightnessOffset,
      exposureGain: exposureGain,
      highlightAdjust: highlightAdjust,
      shadowAdjust: shadowAdjust,
      blackOffset: blackOffset,
      vignette: vignette,
      redGreenRatio: redGreenRatio,
      blueGreenRatio: blueGreenRatio,
      deepBlueContrast: deepBlueContrast,
      contrastStretch: contrastStretch,
      darkBlueSceneLift: darkBlueSceneLift,
      shallowCyanHighlightLift: shallowCyanHighlightLift,
      shallowCyanWaterLift: shallowCyanWaterLift,
      brightShallowCyanDim: brightShallowCyanDim,
      centerX: centerX,
      centerY: centerY,
      maxRadius: maxRadius,
    );
  }

  final int width;
  final int height;
  final int lowLuma;
  final int highLuma;
  final double grayMean;
  final double rGain;
  final double gGain;
  final bool severeGlobalRedLoss;
  final bool blueNotDominant;
  final double bGain;
  final double recovery;
  final double correctionScale;
  final double redRecovery;
  final double requestedContrastStretch;
  final double sat;
  final double vibrance;
  final double contrast;
  final double hazeReduction;
  final double highlightProtection;
  final double invGamma;
  final _PowerCurve gammaCurve;
  final double hueShift;
  final Float64List? hue;
  final double brightnessOffset;
  final double exposureGain;
  final double highlightAdjust;
  final double shadowAdjust;
  final double blackOffset;
  final double vignette;
  final double redGreenRatio;
  final double blueGreenRatio;
  final double deepBlueContrast;
  final double contrastStretch;
  final double darkBlueSceneLift;
  final bool shallowCyanHighlightLift;
  final double shallowCyanWaterLift;
  final double brightShallowCyanDim;
  final double centerX;
  final double centerY;
  final double maxRadius;

  /// Corrects rows `[yStart, yEnd)`. [s] holds source rows from [sRow] on and
  /// must include row `yStart - 1` when `yStart > 0`, because the structure
  /// weight compares each pixel with its upper neighbour. [out] receives
  /// rows from [outRow] on.
  void correctRows(
    Uint8List s,
    int sRow,
    Uint8List out,
    int outRow,
    int yStart,
    int yEnd,
  ) {
    final hue = this.hue;
    for (var y = yStart; y < yEnd; y++) {
      for (var x = 0; x < width; x++) {
        final index = ((y - sRow) * width + x) * 4;
        final outIndex = ((y - outRow) * width + x) * 4;
        var r = s[index].toDouble();
        var g = s[index + 1].toDouble();
        var b = s[index + 2].toDouble();
        final originalR = r;
        final originalG = g;
        final originalB = b;
        final a = s[index + 3];
        final maxUnit = math.max(r, math.max(g, b)) / 255.0;
        final highlightWeight = 1.0 - highlightProtection * maxUnit * maxUnit;
        final openWater = UnderwaterProcessor._openWaterWeight(
          originalR,
          originalG,
          originalB,
        );
        final redLiftScale = UnderwaterProcessor._mix(0.42, 0.18, openWater);
        r +=
            recovery *
            redRecovery *
            redLiftScale *
            math.max(0.0, g - r) *
            (1.0 - r / 255.0) *
            highlightWeight;
        b +=
            recovery *
            0.10 *
            math.max(0.0, g - b) *
            (1.0 - b / 255.0) *
            highlightWeight;
        if (hazeReduction > 0) {
          final haze = math.min(g, b) * 0.08 * hazeReduction;
          r = math.max(0.0, r - haze * 0.25);
          g = math.max(0.0, g - haze);
          b = math.max(0.0, b - haze * 0.75);
        }
        r *= rGain;
        g *= gGain;
        b *= bGain;
        if (contrastStretch > 0) {
          final lumaBefore = math.max(
            1.0,
            0.2126 * r + 0.7152 * g + 0.0722 * b,
          );
          final lumaAfter = UnderwaterProcessor._stretch(
            lumaBefore,
            lowLuma,
            highLuma,
          );
          final lumaScale = UnderwaterProcessor._mix(
            1.0,
            lumaAfter / lumaBefore,
            contrastStretch,
          );
          r *= lumaScale;
          g *= lumaScale;
          b *= lumaScale;
        }
        final cyanMaterial = UnderwaterProcessor._recoverableCyanWeight(
          originalR,
          originalG,
          originalB,
          openWater,
        );
        if (cyanMaterial > 0.001) {
          final lumaNow = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          final redDeficitNow = math.max(0.0, math.max(g, b) - r);
          final neutralR = math.max(r, lumaNow + redDeficitNow * 0.18);
          final neutralG = UnderwaterProcessor._mix(g, lumaNow, 0.22);
          final neutralB = UnderwaterProcessor._mix(b, lumaNow, 0.18);
          final neutralize = _clampD(
            (recovery * (0.38 + redRecovery * 0.16) * cyanMaterial),
            0.0,
            0.74,
          );
          r = UnderwaterProcessor._mix(r, neutralR, neutralize);
          g = UnderwaterProcessor._mix(g, neutralG, neutralize * 0.70);
          b = UnderwaterProcessor._mix(b, neutralB, neutralize * 0.56);
        }
        r = (r - 128.0) * contrast + 128.0;
        g = (g - 128.0) * contrast + 128.0;
        b = (b - 128.0) * contrast + 128.0;
        r = 255.0 * gammaCurve.apply(UnderwaterProcessor._unit(r));
        g = 255.0 * gammaCurve.apply(UnderwaterProcessor._unit(g));
        b = 255.0 * gammaCurve.apply(UnderwaterProcessor._unit(b));
        final maxChannel = math.max(r, math.max(g, b));
        final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        var effectiveSat =
            sat *
            (1.0 + vibrance * (1.0 - _clampD((maxChannel / 255.0), 0.0, 1.0)));
        if (openWater > 0.01) {
          effectiveSat = UnderwaterProcessor._mix(
            effectiveSat,
            math.min(effectiveSat, 0.96),
            openWater * 0.72,
          );
        }
        r = luma + (r - luma) * effectiveSat;
        g = luma + (g - luma) * effectiveSat;
        b = luma + (b - luma) * effectiveSat;

        final tone = UnderwaterProcessor._unit(
          0.2126 * r + 0.7152 * g + 0.0722 * b,
        );
        final shadowsLift = shadowAdjust * (1.0 - tone) * (1.0 - tone);
        final highlightsLift = highlightAdjust * tone * tone;
        r =
            (r + shadowsLift + highlightsLift - blackOffset) * exposureGain +
            brightnessOffset;
        g =
            (g + shadowsLift + highlightsLift - blackOffset) * exposureGain +
            brightnessOffset;
        b =
            (b + shadowsLift + highlightsLift - blackOffset) * exposureGain +
            brightnessOffset;

        if (hue != null) {
          final hr = hue[0] * r + hue[1] * g + hue[2] * b;
          final hg = hue[3] * r + hue[4] * g + hue[5] * b;
          b = hue[6] * r + hue[7] * g + hue[8] * b;
          r = hr;
          g = hg;
        }
        if (darkBlueSceneLift > 0.001) {
          final toneNow = UnderwaterProcessor._unit(
            0.2126 * r + 0.7152 * g + 0.0722 * b,
          );
          final lift =
              darkBlueSceneLift *
              (18.0 + 126.0 * math.pow(toneNow, 1.42).toDouble());
          r += lift * 1.20;
          g += lift * 1.04;
          b += lift * 0.88;
        }
        if (shallowCyanHighlightLift && correctionScale > 0.001) {
          final toneNow = UnderwaterProcessor._unit(
            0.2126 * r + 0.7152 * g + 0.0722 * b,
          );
          final lift =
              10.0 * correctionScale * math.pow(toneNow, 2.2).toDouble();
          r += lift * 1.04;
          g += lift;
          b += lift;
        }
        if (shallowCyanWaterLift > 0.001 && openWater > 0.01) {
          final toneNow = UnderwaterProcessor._unit(
            0.2126 * r + 0.7152 * g + 0.0722 * b,
          );
          final waterLift =
              shallowCyanWaterLift *
              openWater *
              (7.0 + 28.0 * math.pow(1.0 - toneNow, 1.25).toDouble());
          r += waterLift * 0.52;
          g += waterLift * 0.90;
          b += waterLift * 1.18;
        }
        if (brightShallowCyanDim > 0.001) {
          final toneNow = UnderwaterProcessor._unit(
            0.2126 * r + 0.7152 * g + 0.0722 * b,
          );
          final dim =
              brightShallowCyanDim *
              (34.0 + 58.0 * math.pow(toneNow, 1.25).toDouble());
          r -= dim * 1.08;
          g -= dim;
          b -= dim * 0.86;
        }
        if (originalB > originalG * 1.12) {
          final structure = UnderwaterProcessor._localStructureWeight(
            s,
            width,
            x,
            y - sRow,
            originalR,
            originalG,
            originalB,
          );
          if (structure > 0.001) {
            final redDeficit = _clampD(
              ((math.max(originalG, originalB) - originalR) / 175.0),
              0.0,
              1.0,
            );
            final materialWeight = _clampD(
              (structure * redDeficit * (1.0 - openWater * 0.32)),
              0.0,
              0.55,
            );
            final warmRedTarget = math.min(g, b) * 0.82;
            final blueTarget = g * 1.12;
            if (r < warmRedTarget) {
              r = UnderwaterProcessor._mix(
                r,
                warmRedTarget,
                materialWeight * 0.60,
              );
            }
            if (b > blueTarget) {
              b = UnderwaterProcessor._mix(
                b,
                blueTarget,
                materialWeight * 0.42,
              );
            }
          }
        }
        if (originalB <= originalG * 1.12) {
          final surfaceRedTarget = math.min(g, b) * 0.94;
          if (r < surfaceRedTarget) {
            final inputRedLoss = _clampD(
              ((math.min(originalG, originalB) - originalR) / 130.0),
              0.0,
              1.0,
            );
            final neutralWeight = _clampD(
              ((0.18 + inputRedLoss * 0.62) * (1.0 - openWater * 0.25)),
              0.0,
              0.82,
            );
            r = UnderwaterProcessor._mix(r, surfaceRedTarget, neutralWeight);
          }
        }
        if (brightShallowCyanDim > 0.001) {
          final lumaNow = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          final chromaBoost = 1.0 + brightShallowCyanDim * 0.62;
          r = lumaNow + (r - lumaNow) * chromaBoost;
          g = lumaNow + (g - lumaNow) * chromaBoost;
          b = lumaNow + (b - lumaNow) * chromaBoost;
          final materialWarm = _clampD(
            (brightShallowCyanDim * cyanMaterial * (1.0 - openWater * 0.55)),
            0.0,
            1.0,
          );
          if (materialWarm > 0.001) {
            r *= 1.0 + materialWarm * 0.72;
            g *= 1.0 + materialWarm * 0.08;
            b *= 1.0 - materialWarm * 0.44;
            final warmedLuma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
            if (warmedLuma > 1.0) {
              final scale = lumaNow / warmedLuma;
              r *= scale;
              g *= scale;
              b *= scale;
            }
          }
        }
        if (openWater > 0.01) {
          final pureWaterCeiling = UnderwaterProcessor._mix(
            1.32,
            0.74,
            openWater,
          );
          final materialCeiling = UnderwaterProcessor._mix(
            pureWaterCeiling,
            1.05,
            cyanMaterial * 0.92,
          );
          final redCeiling = math.max(g, b) * materialCeiling + 12.0;
          if (r > redCeiling) {
            r = UnderwaterProcessor._mix(r, redCeiling, openWater * 0.78);
          }
        }
        if (vignette > 0.0001) {
          final dx = x - centerX;
          final dy = y - centerY;
          final radius = math.sqrt(dx * dx + dy * dy) / maxRadius;
          final factor = _clampD(
            (1.0 - vignette * 0.55 * radius * radius),
            0.0,
            1.0,
          );
          r *= factor;
          g *= factor;
          b *= factor;
        }
        out[outIndex] = UnderwaterProcessor._byte(r);
        out[outIndex + 1] = UnderwaterProcessor._byte(g);
        out[outIndex + 2] = UnderwaterProcessor._byte(b);
        out[outIndex + 3] = a;
      }
    }
  }
}

/// Scene constants of the local (Retinex-style) fusion pass; sendable to
/// worker isolates like [_CorrectionPlan].
class _FusionPlan {
  _FusionPlan({
    required this.width,
    required this.redGreenRatio,
    required this.blueGreenRatio,
    required this.blueScene,
    required this.darkBlueDepth,
    required this.redLossScene,
    required this.recovery,
    required this.amount,
    required this.retinexPower,
    required this.redRetinex,
    required this.greenRetinex,
    required this.blueRetinex,
  });

  factory _FusionPlan.from(
    RestorationSettings settings,
    _ImageStats stats,
    int width,
  ) {
    final redGreenRatio = stats.meanR / math.max(1.0, stats.meanG);
    final blueGreenRatio = stats.meanB / math.max(1.0, stats.meanG);
    final blueScene = _clampD(((blueGreenRatio - 1.08) / 0.34), 0.0, 1.0);
    final darkBlueDepth = _clampD(((58.0 - stats.lowMidLuma) / 27.0), 0.0, 1.0);
    final redLossScene = _clampD(((0.22 - redGreenRatio) / 0.20), 0.0, 1.0);
    final recovery = _clampD(settings.recovery, 0.0, 1.5);
    final amount = _clampD((0.46 + recovery * 0.28), 0.0, 0.88);

    final retinexPower =
        UnderwaterProcessor._mix(0.52, 0.72, blueScene) *
        (0.82 + recovery * 0.12);
    final redRetinex = _PowerCurve.range(retinexPower, 0.72, 1.52);
    final greenRetinex = _PowerCurve.range(retinexPower * 0.82, 0.78, 1.28);
    final blueRetinex = _PowerCurve.range(retinexPower, 0.68, 1.24);
    return _FusionPlan(
      width: width,
      redGreenRatio: redGreenRatio,
      blueGreenRatio: blueGreenRatio,
      blueScene: blueScene,
      darkBlueDepth: darkBlueDepth,
      redLossScene: redLossScene,
      recovery: recovery,
      amount: amount,
      retinexPower: retinexPower,
      redRetinex: redRetinex,
      greenRetinex: greenRetinex,
      blueRetinex: blueRetinex,
    );
  }

  final int width;
  final double redGreenRatio;
  final double blueGreenRatio;
  final double blueScene;
  final double darkBlueDepth;
  final double redLossScene;
  final double recovery;
  final double amount;
  final double retinexPower;
  final _PowerCurve redRetinex;
  final _PowerCurve greenRetinex;
  final _PowerCurve blueRetinex;

  /// Fuses rows `[yStart, yEnd)` in place. [src] holds original rows from
  /// [srcRow] on and [dst] holds corrected rows from [dstRow] on.
  void fuseRows(
    Uint8List src,
    int srcRow,
    Uint8List dst,
    int dstRow,
    _FusionGuide guide,
    Int32List guideX,
    Int32List guideY,
    int yStart,
    int yEnd,
  ) {
    for (var y = yStart; y < yEnd; y++) {
      final guideRow = guideY[y] * guide.width;
      for (var x = 0; x < width; x++) {
        final srcIndex = ((y - srcRow) * width + x) * 4;
        final index = ((y - dstRow) * width + x) * 4;
        final originalR = src[srcIndex].toDouble();
        final originalG = src[srcIndex + 1].toDouble();
        final originalB = src[srcIndex + 2].toDouble();
        final openWater = UnderwaterProcessor._openWaterWeight(
          originalR,
          originalG,
          originalB,
        );
        final blueGreen = math.max(originalG, originalB);
        final redDeficit = blueGreen <= 1
            ? 0.0
            : _clampD(((blueGreen - originalR) / 165.0), 0.0, 1.0);
        final sample = guideRow + guideX[x];
        final texture = guide.structure[sample];
        final waterSuppression =
            1.0 - openWater * UnderwaterProcessor._mix(0.88, 0.28, texture);
        final material = _clampD(
          (redDeficit *
              (0.14 + texture * 1.72) *
              waterSuppression *
              UnderwaterProcessor._mix(0.38, 1.0, redLossScene)),
          0.0,
          1.0,
        );
        final localContrast = guide.localContrast[sample];
        if (material <= 0.002 && localContrast.abs() <= 0.01) {
          continue;
        }
        final sampleLuma = guide.luma[sample];
        final localR = guide.localR[sample];
        final localG = guide.localG[sample];
        final localB = guide.localB[sample];

        var r = dst[index].toDouble();
        var g = dst[index + 1].toDouble();
        var b = dst[index + 2].toDouble();
        final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        final localTone =
            localContrast * (18.0 + 42.0 * material) * (1.0 - openWater * 0.45);
        final hazeLift =
            material *
            _clampD((1.0 - sampleLuma), 0.0, 1.0) *
            UnderwaterProcessor._mix(
              0.2,
              13.0,
              math.max(blueScene, redLossScene * 0.35),
            );
        final targetLuma = _clampD((luma + localTone + hazeLift), 0.0, 255.0);

        // Deep blue scenes still need to look underwater. Keep a controlled
        // cool separation instead of forcing textured subjects toward gray.
        final targetRg = UnderwaterProcessor._mix(
          1.00,
          UnderwaterProcessor._mix(0.90, 0.84, darkBlueDepth),
          blueScene,
        );
        final targetBg = UnderwaterProcessor._mix(
          0.96,
          UnderwaterProcessor._mix(1.08, 1.15, darkBlueDepth),
          blueScene,
        );
        final targetG =
            targetLuma /
            math.max(0.001, 0.2126 * targetRg + 0.7152 + 0.0722 * targetBg);
        final targetR = targetG * targetRg;
        final targetB = targetG * targetBg;
        final localGray = (localR + localG + localB) / 3.0;
        var retinexR =
            r * redRetinex.apply(localGray / math.max(0.012, localR));
        var retinexG =
            g * greenRetinex.apply(localGray / math.max(0.012, localG));
        var retinexB =
            b * blueRetinex.apply(localGray / math.max(0.012, localB));
        final warmBias = _clampD(
          (material *
              (0.32 + texture * 0.68) *
              UnderwaterProcessor._mix(0.48, 1.0, redLossScene)),
          0.0,
          1.0,
        );
        final deepWarmRed = UnderwaterProcessor._mix(
          0.10,
          0.085,
          darkBlueDepth,
        );
        final deepWarmBlue = UnderwaterProcessor._mix(
          0.055,
          0.045,
          darkBlueDepth,
        );
        retinexR *=
            1.0 +
            warmBias * UnderwaterProcessor._mix(0.08, deepWarmRed, blueScene);
        retinexG *= 1.0 - warmBias * 0.015;
        retinexB *=
            1.0 -
            warmBias * UnderwaterProcessor._mix(0.04, deepWarmBlue, blueScene);
        final retinexLuma =
            0.2126 * retinexR + 0.7152 * retinexG + 0.0722 * retinexB;
        if (retinexLuma > 1.0) {
          final retinexScale = targetLuma / retinexLuma;
          retinexR *= retinexScale;
          retinexG *= retinexScale;
          retinexB *= retinexScale;
        }
        final fusedTargetR = UnderwaterProcessor._mix(targetR, retinexR, 0.68);
        final fusedTargetG = UnderwaterProcessor._mix(targetG, retinexG, 0.68);
        final fusedTargetB = UnderwaterProcessor._mix(targetB, retinexB, 0.68);
        final chromaWeight = _clampD(
          (material * amount * (0.56 + texture * 0.44)),
          0.0,
          0.66,
        );
        final lumaWeight = _clampD(
          ((material * 0.24 + texture * 0.10) * (1.0 - openWater * 0.55)),
          0.0,
          0.32,
        );

        r = UnderwaterProcessor._mix(r, fusedTargetR, chromaWeight);
        g = UnderwaterProcessor._mix(g, fusedTargetG, chromaWeight);
        b = UnderwaterProcessor._mix(b, fusedTargetB, chromaWeight);
        if (lumaWeight > 0.001) {
          final adjustedLuma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          final scale = adjustedLuma <= 1
              ? 1.0
              : UnderwaterProcessor._mix(
                  1.0,
                  targetLuma / adjustedLuma,
                  lumaWeight,
                );
          r *= scale;
          g *= scale;
          b *= scale;
        }
        final brightSandWarm = _clampD(
          blueScene *
              redLossScene *
              redDeficit *
              (1.0 - texture * 0.28) *
              (1.0 - openWater * 0.32) *
              _clampD((sampleLuma - 0.42) / 0.34, 0.0, 1.0),
          0.0,
          1.0,
        );
        final blueMaterialWarm = _clampD(
          blueScene *
                  redLossScene *
                  redDeficit *
                  (0.20 + texture * 0.62) *
                  (1.0 - openWater * 0.72) *
                  _clampD((sampleLuma - 0.18) / 0.54, 0.0, 1.0) +
              brightSandWarm * 0.24,
          0.0,
          1.0,
        );
        if (blueMaterialWarm > 0.001) {
          final preserveLuma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          r *=
              1.0 +
              blueMaterialWarm *
                  UnderwaterProcessor._mix(0.36, 0.28, darkBlueDepth);
          g *=
              1.0 +
              blueMaterialWarm *
                  UnderwaterProcessor._mix(0.05, 0.04, darkBlueDepth);
          b *=
              1.0 -
              blueMaterialWarm *
                  UnderwaterProcessor._mix(0.24, 0.17, darkBlueDepth);
          final warmedLuma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          if (warmedLuma > 1.0) {
            final scale = preserveLuma / warmedLuma;
            r *= scale;
            g *= scale;
            b *= scale;
          }
        }
        dst[index] = UnderwaterProcessor._byte(r);
        dst[index + 1] = UnderwaterProcessor._byte(g);
        dst[index + 2] = UnderwaterProcessor._byte(b);
      }
    }
  }
}
