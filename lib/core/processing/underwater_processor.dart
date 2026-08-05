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
    final requestedContrastStretch = settings.contrastStretch
        .clamp(0.0, 1.0)
        .toDouble();
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
    final deepBlueContrast = ((blueGreenRatio - 1.20) / 0.18)
        .clamp(0.0, 1.0)
        .toDouble();
    final contrastStretch = _mix(
      requestedContrastStretch,
      math.min(1.0, requestedContrastStretch + 0.06),
      deepBlueContrast,
    );
    final darkBlueSceneLift =
        (((55.0 - stats.lowMidLuma) / 30.0).clamp(0.0, 1.0) *
                ((blueGreenRatio - 1.25) / 0.20).clamp(0.0, 1.0) *
                ((0.14 - redGreenRatio) / 0.14).clamp(0.0, 1.0))
            .toDouble();
    final shallowCyanHighlightLift = blueNotDominant
        ? severeGlobalRedLoss && stats.lowMidLuma < 82
        : false;
    final shallowCyanWaterLift =
        blueNotDominant && severeGlobalRedLoss && stats.lowMidLuma < 82
        ? (((82.0 - stats.lowMidLuma) / 30.0).clamp(0.0, 1.0) *
                  ((1.20 - blueGreenRatio) / 0.25).clamp(0.0, 1.0))
              .toDouble()
        : 0.0;
    final brightShallowCyanDim = blueNotDominant && severeGlobalRedLoss
        ? (((stats.lowMidLuma - 76.0) / 36.0).clamp(0.0, 1.0) *
                  ((1.20 - blueGreenRatio) / 0.25).clamp(0.0, 1.0))
              .toDouble()
        : 0.0;
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
              (18.0 + 126.0 * math.pow(toneNow, 1.42).toDouble());
          r += lift * 1.20;
          g += lift * 1.04;
          b += lift * 0.88;
        }
        if (shallowCyanHighlightLift) {
          final toneNow = _unit(0.2126 * r + 0.7152 * g + 0.0722 * b);
          final lift = 10.0 * math.pow(toneNow, 2.2).toDouble();
          r += lift * 1.04;
          g += lift;
          b += lift;
        }
        if (shallowCyanWaterLift > 0.001 && openWater > 0.01) {
          final toneNow = _unit(0.2126 * r + 0.7152 * g + 0.0722 * b);
          final waterLift =
              shallowCyanWaterLift *
              openWater *
              (7.0 + 28.0 * math.pow(1.0 - toneNow, 1.25).toDouble());
          r += waterLift * 0.52;
          g += waterLift * 0.90;
          b += waterLift * 1.18;
        }
        if (brightShallowCyanDim > 0.001) {
          final toneNow = _unit(0.2126 * r + 0.7152 * g + 0.0722 * b);
          final dim =
              brightShallowCyanDim *
              (34.0 + 58.0 * math.pow(toneNow, 1.25).toDouble());
          r -= dim * 1.08;
          g -= dim;
          b -= dim * 0.86;
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
        if (brightShallowCyanDim > 0.001) {
          final lumaNow = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          final chromaBoost = 1.0 + brightShallowCyanDim * 0.62;
          r = lumaNow + (r - lumaNow) * chromaBoost;
          g = lumaNow + (g - lumaNow) * chromaBoost;
          b = lumaNow + (b - lumaNow) * chromaBoost;
          final materialWarm =
              (brightShallowCyanDim * cyanMaterial * (1.0 - openWater * 0.55))
                  .clamp(0.0, 1.0)
                  .toDouble();
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
    final fused = _retinexFusion(source, output, stats, settings, quality);
    final detail =
        (settings.sharpness + settings.clarity * 0.75)
            .clamp(0.0, 1.2)
            .toDouble() *
        quality.detailScale;
    return detail <= 0.001 ? fused : _unsharp3x3(fused, detail);
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

  static img.Image _retinexFusion(
    img.Image source,
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
    final out = corrected.clone();
    final redGreenRatio = stats.meanR / math.max(1.0, stats.meanG);
    final blueGreenRatio = stats.meanB / math.max(1.0, stats.meanG);
    final blueScene = ((blueGreenRatio - 1.08) / 0.34)
        .clamp(0.0, 1.0)
        .toDouble();
    final darkBlueDepth = ((58.0 - stats.lowMidLuma) / 27.0)
        .clamp(0.0, 1.0)
        .toDouble();
    final redLossScene = ((0.22 - redGreenRatio) / 0.20)
        .clamp(0.0, 1.0)
        .toDouble();
    final recovery = settings.recovery.clamp(0.0, 1.5).toDouble();
    final amount = (0.46 + recovery * 0.28).clamp(0.0, 0.88).toDouble();

    for (var y = 0; y < corrected.height; y++) {
      for (var x = 0; x < corrected.width; x++) {
        final original = source.getPixel(x, y);
        final current = corrected.getPixel(x, y);
        final originalR = original.r.toDouble();
        final originalG = original.g.toDouble();
        final originalB = original.b.toDouble();
        final openWater = _openWaterWeight(originalR, originalG, originalB);
        final blueGreen = math.max(originalG, originalB);
        final redDeficit = blueGreen <= 1
            ? 0.0
            : ((blueGreen - originalR) / 165.0).clamp(0.0, 1.0).toDouble();
        final sample = guide.sample(x, y, corrected.width, corrected.height);
        final texture = sample.structure;
        final waterSuppression = 1.0 - openWater * _mix(0.88, 0.28, texture);
        final material =
            (redDeficit *
                    (0.14 + texture * 1.72) *
                    waterSuppression *
                    _mix(0.38, 1.0, redLossScene))
                .clamp(0.0, 1.0)
                .toDouble();
        if (material <= 0.002 && sample.localContrast.abs() <= 0.01) {
          continue;
        }

        var r = current.r.toDouble();
        var g = current.g.toDouble();
        var b = current.b.toDouble();
        final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        final localTone =
            sample.localContrast *
            (18.0 + 42.0 * material) *
            (1.0 - openWater * 0.45);
        final hazeLift =
            material *
            (1.0 - sample.luma).clamp(0.0, 1.0).toDouble() *
            _mix(0.2, 13.0, math.max(blueScene, redLossScene * 0.35));
        final targetLuma = (luma + localTone + hazeLift)
            .clamp(0.0, 255.0)
            .toDouble();

        // Deep blue scenes still need to look underwater. Keep a controlled
        // cool separation instead of forcing textured subjects toward gray.
        final targetRg = _mix(1.00, _mix(0.90, 0.84, darkBlueDepth), blueScene);
        final targetBg = _mix(0.96, _mix(1.08, 1.15, darkBlueDepth), blueScene);
        final targetG =
            targetLuma /
            math.max(0.001, 0.2126 * targetRg + 0.7152 + 0.0722 * targetBg);
        final targetR = targetG * targetRg;
        final targetB = targetG * targetBg;
        final localGray = (sample.localR + sample.localG + sample.localB) / 3.0;
        final retinexPower =
            _mix(0.52, 0.72, blueScene) * (0.82 + recovery * 0.12);
        var retinexR =
            r *
            math
                .pow(
                  (localGray / math.max(0.012, sample.localR)).clamp(
                    0.72,
                    1.52,
                  ),
                  retinexPower,
                )
                .toDouble();
        var retinexG =
            g *
            math
                .pow(
                  (localGray / math.max(0.012, sample.localG)).clamp(
                    0.78,
                    1.28,
                  ),
                  retinexPower * 0.82,
                )
                .toDouble();
        var retinexB =
            b *
            math
                .pow(
                  (localGray / math.max(0.012, sample.localB)).clamp(
                    0.68,
                    1.24,
                  ),
                  retinexPower,
                )
                .toDouble();
        final warmBias =
            (material * (0.32 + texture * 0.68) * _mix(0.48, 1.0, redLossScene))
                .clamp(0.0, 1.0)
                .toDouble();
        final deepWarmRed = _mix(0.10, 0.085, darkBlueDepth);
        final deepWarmBlue = _mix(0.055, 0.045, darkBlueDepth);
        retinexR *= 1.0 + warmBias * _mix(0.08, deepWarmRed, blueScene);
        retinexG *= 1.0 - warmBias * 0.015;
        retinexB *= 1.0 - warmBias * _mix(0.04, deepWarmBlue, blueScene);
        final retinexLuma =
            0.2126 * retinexR + 0.7152 * retinexG + 0.0722 * retinexB;
        if (retinexLuma > 1.0) {
          final retinexScale = targetLuma / retinexLuma;
          retinexR *= retinexScale;
          retinexG *= retinexScale;
          retinexB *= retinexScale;
        }
        final fusedTargetR = _mix(targetR, retinexR, 0.68);
        final fusedTargetG = _mix(targetG, retinexG, 0.68);
        final fusedTargetB = _mix(targetB, retinexB, 0.68);
        final chromaWeight = (material * amount * (0.56 + texture * 0.44))
            .clamp(0.0, 0.66);
        final lumaWeight =
            ((material * 0.24 + sample.structure * 0.10) *
                    (1.0 - openWater * 0.55))
                .clamp(0.0, 0.32)
                .toDouble();

        r = _mix(r, fusedTargetR, chromaWeight);
        g = _mix(g, fusedTargetG, chromaWeight);
        b = _mix(b, fusedTargetB, chromaWeight);
        if (lumaWeight > 0.001) {
          final adjustedLuma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          final scale = adjustedLuma <= 1
              ? 1.0
              : _mix(1.0, targetLuma / adjustedLuma, lumaWeight);
          r *= scale;
          g *= scale;
          b *= scale;
        }
        final brightSandWarm =
            (blueScene *
                    redLossScene *
                    redDeficit *
                    (1.0 - texture * 0.28) *
                    (1.0 - openWater * 0.32) *
                    ((sample.luma - 0.42) / 0.34).clamp(0.0, 1.0))
                .clamp(0.0, 1.0)
                .toDouble();
        final blueMaterialWarm =
            (blueScene *
                        redLossScene *
                        redDeficit *
                        (0.20 + texture * 0.62) *
                        (1.0 - openWater * 0.72) *
                        ((sample.luma - 0.18) / 0.54).clamp(0.0, 1.0) +
                    brightSandWarm * 0.24)
                .clamp(0.0, 1.0)
                .toDouble();
        if (blueMaterialWarm > 0.001) {
          final preserveLuma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          r *= 1.0 + blueMaterialWarm * _mix(0.36, 0.28, darkBlueDepth);
          g *= 1.0 + blueMaterialWarm * _mix(0.05, 0.04, darkBlueDepth);
          b *= 1.0 - blueMaterialWarm * _mix(0.24, 0.17, darkBlueDepth);
          final warmedLuma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          if (warmedLuma > 1.0) {
            final scale = preserveLuma / warmedLuma;
            r *= scale;
            g *= scale;
            b *= scale;
          }
        }
        out.setPixelRgba(x, y, _byte(r), _byte(g), _byte(b), current.a.toInt());
      }
    }
    return out;
  }

  static double _mix(double a, double b, double t) =>
      a + (b - a) * t.clamp(0.0, 1.0).toDouble();
  static double _stretch(double v, int low, int high) => high <= low
      ? v
      : ((v - low) * 255.0 / (high - low)).clamp(0.0, 255.0).toDouble();
  static double _unit(double v) => (v / 255.0).clamp(0.0, 1.0).toDouble();
  static int _byte(num v) => v.round().clamp(0, 255).toInt();
}

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
  final List<double> luma;
  final List<double> localR;
  final List<double> localG;
  final List<double> localB;
  final List<double> localContrast;
  final List<double> structure;

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
    final luma = List<double>.filled(width * height, 0);
    final red = List<double>.filled(width * height, 0);
    final green = List<double>.filled(width * height, 0);
    final blue = List<double>.filled(width * height, 0);
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
    final localContrast = List<double>.filled(width * height, 0);
    final structure = List<double>.filled(width * height, 0);
    for (var i = 0; i < luma.length; i++) {
      final smallDetail = luma[i] - smallBlur[i];
      final mediumDetail = luma[i] - mediumBlur[i];
      final largeDetail = luma[i] - largeBlur[i];
      localContrast[i] =
          (smallDetail * 0.12 + mediumDetail * 0.32 + largeDetail * 0.56).clamp(
            -0.45,
            0.45,
          );
      structure[i] = (smallDetail.abs() * 5.5 + mediumDetail.abs() * 3.0)
          .clamp(0.0, 1.0)
          .toDouble();
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

  _FusionSample sample(int x, int y, int sourceWidth, int sourceHeight) {
    final gx = sourceWidth <= 1
        ? 0
        : (x * (width - 1) / (sourceWidth - 1)).round().clamp(0, width - 1);
    final gy = sourceHeight <= 1
        ? 0
        : (y * (height - 1) / (sourceHeight - 1)).round().clamp(0, height - 1);
    final index = gy * width + gx;
    return _FusionSample(
      luma: luma[index],
      localR: localR[index],
      localG: localG[index],
      localB: localB[index],
      localContrast: localContrast[index],
      structure: structure[index],
    );
  }

  static List<double> _boxBlur(
    List<double> input,
    int width,
    int height,
    int radius,
  ) {
    if (radius <= 0) return List<double>.from(input);
    final horizontal = List<double>.filled(input.length, 0);
    final output = List<double>.filled(input.length, 0);
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

class _FusionSample {
  const _FusionSample({
    required this.luma,
    required this.localR,
    required this.localG,
    required this.localB,
    required this.localContrast,
    required this.structure,
  });

  final double luma;
  final double localR;
  final double localG;
  final double localB;
  final double localContrast;
  final double structure;
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
