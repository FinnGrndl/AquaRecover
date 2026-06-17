import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/restoration_settings.dart';

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

  img.Image restoreImage(img.Image source, RestorationSettings settings) {
    _validateImageSize(source);
    final stats = _ImageStats.from(source);
    final output = img.Image(
      width: source.width,
      height: source.height,
      numChannels: 4,
    );
    final grayMean = (stats.meanR + stats.meanG + stats.meanB) / 3.0;
    final rGain = _mix(
      1.0,
      (grayMean / math.max(1.0, stats.meanR)).clamp(0.75, 2.05).toDouble(),
      settings.autoWhiteBalance,
    );
    final gGain = _mix(
      1.0,
      (grayMean / math.max(1.0, stats.meanG)).clamp(0.82, 1.28).toDouble(),
      settings.autoWhiteBalance * 0.45,
    );
    final severeGlobalRedLoss = stats.meanR / math.max(1.0, stats.meanG) < 0.12;
    final blueNotDominant =
        severeGlobalRedLoss && stats.meanB <= stats.meanG * 1.12;
    final bGain = _mix(
      1.0,
      (grayMean / math.max(1.0, stats.meanB))
          .clamp(blueNotDominant ? 0.90 : 0.58, 1.14)
          .toDouble(),
      settings.autoWhiteBalance * (blueNotDominant ? 0.26 : 0.62),
    );
    final recovery = settings.recovery.clamp(0.0, 1.5).toDouble();
    final redRecovery = settings.redRecovery.clamp(0.0, 2.5).toDouble();
    final contrastStretch = settings.contrastStretch.clamp(0.0, 1.0).toDouble();
    final sat = settings.saturation.clamp(0.0, 3.0).toDouble();
    final vibrance = settings.vibrance.clamp(0.0, 1.0).toDouble();
    final contrast = settings.contrast.clamp(0.1, 3.0).toDouble();
    final hazeReduction = settings.hazeReduction.clamp(0.0, 1.0).toDouble();
    final highlightProtection = settings.highlightProtection
        .clamp(0.0, 1.0)
        .toDouble();
    final invGamma = 1.0 / settings.gamma.clamp(0.1, 3.0).toDouble();
    final hueShift = settings.hue.clamp(-1.0, 1.0).toDouble() * math.pi;
    final brightnessOffset =
        settings.brightness.clamp(-1.0, 1.0).toDouble() * 70.0;
    final exposureGain = math
        .pow(2.0, settings.exposure.clamp(-1.0, 1.0).toDouble())
        .toDouble();
    final highlightAdjust =
        settings.highlights.clamp(-1.0, 1.0).toDouble() * 90.0;
    final shadowAdjust = settings.shadows.clamp(-1.0, 1.0).toDouble() * 90.0;
    final blackOffset = settings.blackPoint.clamp(0.0, 1.0).toDouble() * 120.0;
    final vignette = settings.vignette.clamp(0.0, 1.0).toDouble();
    final redGreenRatio = stats.meanR / math.max(1.0, stats.meanG);
    final blueGreenRatio = stats.meanB / math.max(1.0, stats.meanG);
    final darkBlueSceneLift =
        (((55.0 - stats.lowMidLuma) / 30.0).clamp(0.0, 1.0) *
                ((blueGreenRatio - 1.25) / 0.20).clamp(0.0, 1.0) *
                ((0.14 - redGreenRatio) / 0.14).clamp(0.0, 1.0))
            .toDouble();
    final shallowCyanHighlightLift = blueNotDominant
        ? severeGlobalRedLoss
        : false;
    final centerX = (source.width - 1) / 2.0;
    final centerY = (source.height - 1) / 2.0;
    final maxRadius = math
        .sqrt(centerX * centerX + centerY * centerY)
        .clamp(1.0, double.infinity)
        .toDouble();

    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        final p = source.getPixel(x, y);
        var r = p.r.toDouble();
        var g = p.g.toDouble();
        var b = p.b.toDouble();
        final originalR = r;
        final originalG = g;
        final originalB = b;
        final a = p.a.toInt();
        final highlightWeight =
            1.0 -
            highlightProtection *
                math.pow(math.max(r, math.max(g, b)) / 255.0, 2.0).toDouble();
        final openWater = _openWaterWeight(originalR, originalG, originalB);
        final redLiftScale = _mix(0.42, 0.18, openWater);
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
          final lumaAfter = _stretch(lumaBefore, stats.lowLuma, stats.highLuma);
          final lumaScale = _mix(1.0, lumaAfter / lumaBefore, contrastStretch);
          r *= lumaScale;
          g *= lumaScale;
          b *= lumaScale;
        }
        final cyanMaterial = _recoverableCyanWeight(
          originalR,
          originalG,
          originalB,
          openWater,
        );
        if (cyanMaterial > 0.001) {
          final lumaNow = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          final redDeficitNow = math.max(0.0, math.max(g, b) - r);
          final neutralR = math.max(r, lumaNow + redDeficitNow * 0.18);
          final neutralG = _mix(g, lumaNow, 0.22);
          final neutralB = _mix(b, lumaNow, 0.18);
          final neutralize =
              (recovery * (0.38 + redRecovery * 0.16) * cyanMaterial)
                  .clamp(0.0, 0.74)
                  .toDouble();
          r = _mix(r, neutralR, neutralize);
          g = _mix(g, neutralG, neutralize * 0.70);
          b = _mix(b, neutralB, neutralize * 0.56);
        }
        r = (r - 128.0) * contrast + 128.0;
        g = (g - 128.0) * contrast + 128.0;
        b = (b - 128.0) * contrast + 128.0;
        r = 255.0 * math.pow(_unit(r), invGamma).toDouble();
        g = 255.0 * math.pow(_unit(g), invGamma).toDouble();
        b = 255.0 * math.pow(_unit(b), invGamma).toDouble();
        final maxChannel = math.max(r, math.max(g, b));
        final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        var effectiveSat =
            sat *
            (1.0 + vibrance * (1.0 - (maxChannel / 255.0).clamp(0.0, 1.0)));
        if (openWater > 0.01) {
          effectiveSat = _mix(
            effectiveSat,
            math.min(effectiveSat, 0.96),
            openWater * 0.72,
          );
        }
        r = luma + (r - luma) * effectiveSat;
        g = luma + (g - luma) * effectiveSat;
        b = luma + (b - luma) * effectiveSat;

        final tone = _unit(0.2126 * r + 0.7152 * g + 0.0722 * b);
        final shadowsLift = shadowAdjust * math.pow(1.0 - tone, 2.0).toDouble();
        final highlightsLift = highlightAdjust * math.pow(tone, 2.0).toDouble();
        r =
            (r + shadowsLift + highlightsLift - blackOffset) * exposureGain +
            brightnessOffset;
        g =
            (g + shadowsLift + highlightsLift - blackOffset) * exposureGain +
            brightnessOffset;
        b =
            (b + shadowsLift + highlightsLift - blackOffset) * exposureGain +
            brightnessOffset;

        if (hueShift.abs() > 0.0001) {
          final shifted = _rotateHue(r, g, b, hueShift);
          r = shifted.$1;
          g = shifted.$2;
          b = shifted.$3;
        }
        if (darkBlueSceneLift > 0.001) {
          final toneNow = _unit(0.2126 * r + 0.7152 * g + 0.0722 * b);
          final lift =
              darkBlueSceneLift *
              (14.0 + 98.0 * math.pow(toneNow, 1.55).toDouble());
          r += lift * 1.16;
          g += lift;
          b += lift * 0.94;
        }
        if (shallowCyanHighlightLift) {
          final toneNow = _unit(0.2126 * r + 0.7152 * g + 0.0722 * b);
          final lift = 10.0 * math.pow(toneNow, 2.2).toDouble();
          r += lift * 1.04;
          g += lift;
          b += lift;
        }
        if (originalB > originalG * 1.12) {
          final structure = _localStructureWeight(
            source,
            x,
            y,
            originalR,
            originalG,
            originalB,
          );
          if (structure > 0.001) {
            final redDeficit =
                ((math.max(originalG, originalB) - originalR) / 175.0)
                    .clamp(0.0, 1.0)
                    .toDouble();
            final materialWeight =
                (structure * redDeficit * (1.0 - openWater * 0.32))
                    .clamp(0.0, 0.55)
                    .toDouble();
            final warmRedTarget = math.min(g, b) * 0.82;
            final blueTarget = g * 1.12;
            if (r < warmRedTarget) {
              r = _mix(r, warmRedTarget, materialWeight * 0.60);
            }
            if (b > blueTarget) {
              b = _mix(b, blueTarget, materialWeight * 0.42);
            }
          }
        }
        if (originalB <= originalG * 1.12) {
          final surfaceRedTarget = math.min(g, b) * 0.94;
          if (r < surfaceRedTarget) {
            final inputRedLoss =
                ((math.min(originalG, originalB) - originalR) / 130.0)
                    .clamp(0.0, 1.0)
                    .toDouble();
            final neutralWeight =
                ((0.18 + inputRedLoss * 0.62) * (1.0 - openWater * 0.25))
                    .clamp(0.0, 0.82)
                    .toDouble();
            r = _mix(r, surfaceRedTarget, neutralWeight);
          }
        }
        if (openWater > 0.01) {
          final pureWaterCeiling = _mix(1.32, 0.74, openWater);
          final materialCeiling = _mix(
            pureWaterCeiling,
            1.05,
            cyanMaterial * 0.92,
          );
          final redCeiling = math.max(g, b) * materialCeiling + 12.0;
          if (r > redCeiling) r = _mix(r, redCeiling, openWater * 0.78);
        }
        if (vignette > 0.0001) {
          final dx = x - centerX;
          final dy = y - centerY;
          final radius = math.sqrt(dx * dx + dy * dy) / maxRadius;
          final factor = (1.0 - vignette * 0.55 * radius * radius)
              .clamp(0.0, 1.0)
              .toDouble();
          r *= factor;
          g *= factor;
          b *= factor;
        }
        output.setPixelRgba(x, y, _byte(r), _byte(g), _byte(b), a);
      }
    }
    final detail = (settings.sharpness + settings.clarity * 0.75)
        .clamp(0.0, 1.2)
        .toDouble();
    return detail <= 0.001 ? output : _unsharp3x3(output, detail);
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

  static (double, double, double) _rotateHue(
    double r,
    double g,
    double b,
    double radians,
  ) {
    final cosA = math.cos(radians);
    final sinA = math.sin(radians);
    final nr =
        (.213 + cosA * .787 - sinA * .213) * r +
        (.715 - cosA * .715 - sinA * .715) * g +
        (.072 - cosA * .072 + sinA * .928) * b;
    final ng =
        (.213 - cosA * .213 + sinA * .143) * r +
        (.715 + cosA * .285 + sinA * .140) * g +
        (.072 - cosA * .072 - sinA * .283) * b;
    final nb =
        (.213 - cosA * .213 - sinA * .787) * r +
        (.715 - cosA * .715 + sinA * .715) * g +
        (.072 + cosA * .928 + sinA * .072) * b;
    return (nr, ng, nb);
  }

  static double _openWaterWeight(double r, double g, double b) {
    final blueGreen = math.max(g, b);
    if (blueGreen <= 1) return 0;
    final redDeficit = ((blueGreen - r) / 165.0).clamp(0.0, 1.0).toDouble();
    final blueDominance = ((b - r) / 180.0).clamp(0.0, 1.0).toDouble();
    final greenDominance = ((g - r) / 180.0).clamp(0.0, 1.0).toDouble();
    final chroma =
        ((math.max(r, math.max(g, b)) - math.min(r, math.min(g, b))) / 140.0)
            .clamp(0.0, 1.0)
            .toDouble();
    return (redDeficit *
            (0.58 * blueDominance + 0.42 * greenDominance) *
            chroma)
        .clamp(0.0, 1.0)
        .toDouble();
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
    final redDeficit = ((blueGreen - r) / 170.0).clamp(0.0, 1.0).toDouble();
    final brightSurface = ((luma - 42.0) / 132.0).clamp(0.0, 1.0).toDouble();
    final notPureWater = (1.0 - openWater * 0.52).clamp(0.18, 1.0).toDouble();
    return (redDeficit * brightSurface * notPureWater)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  static double _localStructureWeight(
    img.Image source,
    int x,
    int y,
    double r,
    double g,
    double b,
  ) {
    if (source.width < 2 || source.height < 2) return 0;
    final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    var diff = 0.0;
    var samples = 0;
    if (x > 0) {
      final p = source.getPixel(x - 1, y);
      diff += (luma - _pixelLuma(p)).abs();
      samples++;
    }
    if (y > 0) {
      final p = source.getPixel(x, y - 1);
      diff += (luma - _pixelLuma(p)).abs();
      samples++;
    }
    if (samples == 0) return 0;
    return ((diff / samples - 4.0) / 34.0).clamp(0.0, 1.0).toDouble();
  }

  static double _pixelLuma(img.Pixel p) =>
      0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b;

  static double _mix(double a, double b, double t) =>
      a + (b - a) * t.clamp(0.0, 1.0).toDouble();
  static double _stretch(double v, int low, int high) => high <= low
      ? v
      : ((v - low) * 255.0 / (high - low)).clamp(0.0, 255.0).toDouble();
  static double _unit(double v) => (v / 255.0).clamp(0.0, 1.0).toDouble();
  static int _byte(num v) => v.round().clamp(0, 255).toInt();
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

  factory _ImageStats.from(img.Image image) {
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
        final p = image.getPixel(x, y);
        final r = p.r.toInt().clamp(0, 255).toInt(),
            g = p.g.toInt().clamp(0, 255).toInt(),
            b = p.b.toInt().clamp(0, 255).toInt();
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
