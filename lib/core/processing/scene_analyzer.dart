import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../models/restoration_settings.dart';

/// The dominant water cast of an underwater scene.
enum WaterType { blue, green, neutral }

/// Global colour statistics of a frame plus a suggested starting preset.
///
/// The suggestion is a heuristic, not a classifier: it looks at how much red
/// is missing relative to green and blue, which channel dominates the water,
/// and how bright the scene is. It is meant to pick a sensible preset before
/// fine-tuning, in the app or through the MCP server.
class SceneAnalysis {
  const SceneAnalysis({
    required this.width,
    required this.height,
    required this.meanR,
    required this.meanG,
    required this.meanB,
    required this.medianLuma,
    required this.lowLuma,
    required this.highLuma,
    required this.clippedHighlights,
    required this.waterType,
    required this.suggestedPreset,
    required this.suggestedStrength,
    required this.reasons,
  });

  final int width;
  final int height;
  final double meanR;
  final double meanG;
  final double meanB;
  final int medianLuma;
  final int lowLuma;
  final int highLuma;

  /// Share of sampled pixels with a channel at 250 or above.
  final double clippedHighlights;
  final WaterType waterType;
  final RestorationPreset suggestedPreset;
  final double suggestedStrength;
  final List<String> reasons;

  double get redGreenRatio => meanR / math.max(1.0, meanG);
  double get blueGreenRatio => meanB / math.max(1.0, meanG);

  /// 0 when red is intact, 1 when red is essentially gone.
  double get redLoss {
    final reference = math.max(meanG, meanB);
    if (reference <= 1) return 0;
    return ((reference - meanR) / reference).clamp(0.0, 1.0).toDouble();
  }

  RestorationSettings get suggestedSettings =>
      suggestedPreset.settingsAtStrength(suggestedStrength);

  Map<String, Object?> toJson() => {
    'width': width,
    'height': height,
    'meanRgb': [_round(meanR), _round(meanG), _round(meanB)],
    'redGreenRatio': _round(redGreenRatio, 3),
    'blueGreenRatio': _round(blueGreenRatio, 3),
    'redLoss': _round(redLoss, 3),
    'medianLuma': medianLuma,
    'lowLuma': lowLuma,
    'highLuma': highLuma,
    'clippedHighlights': _round(clippedHighlights, 4),
    'waterType': waterType.name,
    'suggestedPreset': suggestedPreset.name,
    'suggestedPresetLabel': suggestedPreset.label,
    'suggestedStrength': _round(suggestedStrength, 2),
    'reasons': reasons,
  };

  static double _round(double value, [int digits = 1]) {
    final factor = math.pow(10, digits);
    return (value * factor).round() / factor;
  }
}

class SceneAnalyzer {
  const SceneAnalyzer();

  /// Samples at most ~60k pixels, so the cost is independent of resolution.
  SceneAnalysis analyze(img.Image image) {
    final pixelCount = image.width * image.height;
    final stride = math.max(1, math.sqrt(pixelCount / 60000.0).floor());
    final histLuma = List<int>.filled(256, 0);
    var count = 0;
    var clipped = 0;
    var sumR = 0.0, sumG = 0.0, sumB = 0.0;
    final maxValue = image.maxChannelValue.toDouble();
    final scale = maxValue <= 0 ? 1.0 : 255.0 / maxValue;
    for (var y = 0; y < image.height; y += stride) {
      for (var x = 0; x < image.width; x += stride) {
        final pixel = image.getPixel(x, y);
        final r = (pixel.r * scale).clamp(0, 255).toDouble();
        final g = (pixel.g * scale).clamp(0, 255).toDouble();
        final b = (pixel.b * scale).clamp(0, 255).toDouble();
        sumR += r;
        sumG += g;
        sumB += b;
        if (r >= 250 || g >= 250 || b >= 250) clipped++;
        histLuma[(0.2126 * r + 0.7152 * g + 0.0722 * b).round().clamp(
          0,
          255,
        )]++;
        count++;
      }
    }
    final n = math.max(1, count);
    return classify(
      width: image.width,
      height: image.height,
      meanR: sumR / n,
      meanG: sumG / n,
      meanB: sumB / n,
      medianLuma: _percentile(histLuma, count, .5),
      lowLuma: _percentile(histLuma, count, .01),
      highLuma: _percentile(histLuma, count, .995),
      clippedHighlights: clipped / n,
    );
  }

  /// Derives the water type and preset from already-measured statistics.
  SceneAnalysis classify({
    required int width,
    required int height,
    required double meanR,
    required double meanG,
    required double meanB,
    required int medianLuma,
    required int lowLuma,
    required int highLuma,
    required double clippedHighlights,
  }) {
    final reasons = <String>[];
    final redGreen = meanR / math.max(1.0, meanG);
    final blueGreen = meanB / math.max(1.0, meanG);
    final reference = math.max(meanG, meanB);
    final redLoss = reference <= 1
        ? 0.0
        : ((reference - meanR) / reference).clamp(0.0, 1.0).toDouble();

    final WaterType water;
    if (redLoss < .18) {
      water = WaterType.neutral;
    } else if (blueGreen >= 1.05) {
      water = WaterType.blue;
    } else {
      water = WaterType.green;
    }

    RestorationPreset preset;
    if (water == WaterType.neutral) {
      if (clippedHighlights > .02 && redGreen > .9) {
        preset = RestorationPreset.artificialLight;
        reasons.add(
          'Colours are close to neutral and highlights clip, which is typical '
          'for strobe or video-light shots.',
        );
      } else if (redGreen > .55 && redLoss > .08) {
        preset = RestorationPreset.redFilter;
        reasons.add(
          'Red is mostly present but slightly low, as with a red dive filter.',
        );
      } else {
        preset = RestorationPreset.natural;
        reasons.add('Little red is missing, so only a gentle correction.');
      }
    } else if (water == WaterType.green) {
      preset = RestorationPreset.greenWater;
      reasons.add(
        'Green dominates blue (blue/green ${blueGreen.toStringAsFixed(2)}), '
        'typical for plankton-rich or lake water.',
      );
    } else if (redLoss > .72 && medianLuma < 90) {
      preset = RestorationPreset.deep;
      reasons.add(
        'Almost no red remains and the scene is dark, which points to depth.',
      );
    } else if (medianLuma > 125 && redLoss < .55) {
      preset = RestorationPreset.shallow;
      reasons.add('Bright, moderately blue scene, typical for shallow water.');
    } else {
      preset = RestorationPreset.auto;
      reasons.add('Typical blue water cast; the balanced default fits.');
    }
    if (clippedHighlights > .05 &&
        preset != RestorationPreset.artificialLight) {
      reasons.add(
        '${(clippedHighlights * 100).toStringAsFixed(1)} % of pixels clip; '
        'consider lowering highlights or raising highlight protection.',
      );
    }

    final strength = switch (preset) {
      RestorationPreset.natural ||
      RestorationPreset.redFilter => (.55 + redLoss).clamp(.5, 1.0).toDouble(),
      RestorationPreset.shallow => (.6 + redLoss * .6).clamp(.6, 1.0),
      _ => (.7 + redLoss * .4).clamp(.7, 1.0).toDouble(),
    };
    return SceneAnalysis(
      width: width,
      height: height,
      meanR: meanR,
      meanG: meanG,
      meanB: meanB,
      medianLuma: medianLuma,
      lowLuma: lowLuma,
      highLuma: highLuma,
      clippedHighlights: clippedHighlights,
      waterType: water,
      suggestedPreset: preset,
      suggestedStrength: strength.toDouble(),
      reasons: reasons,
    );
  }

  static int _percentile(List<int> hist, int total, double p) {
    final target = math.max(1, (total * p).round());
    var running = 0;
    for (var i = 0; i < hist.length; i++) {
      running += hist[i];
      if (running >= target) return i;
    }
    return hist.length - 1;
  }
}
