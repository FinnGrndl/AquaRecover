import 'package:aqua_recover/core/models/restoration_settings.dart';
import 'package:aqua_recover/core/processing/scene_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

SceneAnalysis _classify({
  required double r,
  required double g,
  required double b,
  int median = 100,
  double clipped = 0,
}) => const SceneAnalyzer().classify(
  width: 10,
  height: 10,
  meanR: r,
  meanG: g,
  meanB: b,
  medianLuma: median,
  lowLuma: 10,
  highLuma: 220,
  clippedHighlights: clipped,
);

void main() {
  test('deep dark blue water suggests the deep preset', () {
    final analysis = _classify(r: 12, g: 70, b: 110, median: 60);
    expect(analysis.waterType, WaterType.blue);
    expect(analysis.suggestedPreset, RestorationPreset.deep);
    expect(analysis.suggestedStrength, closeTo(1, .05));
  });

  test('green-dominant water suggests the green water preset', () {
    final analysis = _classify(r: 40, g: 130, b: 105);
    expect(analysis.waterType, WaterType.green);
    expect(analysis.suggestedPreset, RestorationPreset.greenWater);
  });

  test('bright shallow scenes suggest the shallow preset', () {
    final analysis = _classify(r: 90, g: 160, b: 185, median: 150);
    expect(analysis.suggestedPreset, RestorationPreset.shallow);
  });

  test('strobe-lit neutral scenes suggest artificial light', () {
    final analysis = _classify(r: 140, g: 135, b: 130, clipped: .04);
    expect(analysis.waterType, WaterType.neutral);
    expect(analysis.suggestedPreset, RestorationPreset.artificialLight);
  });

  test('suggested settings follow the preset at the suggested strength', () {
    final analysis = _classify(r: 40, g: 110, b: 140);
    expect(
      analysis.suggestedSettings.toJson(),
      analysis.suggestedPreset
          .settingsAtStrength(analysis.suggestedStrength)
          .toJson(),
    );
  });
}
