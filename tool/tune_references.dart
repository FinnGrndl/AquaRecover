import 'dart:io';
import 'dart:math' as math;

import 'package:aqua_recover/core/models/restoration_settings.dart';
import 'package:aqua_recover/core/processing/underwater_processor.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final outDir = Directory(args.isEmpty ? '/tmp/aqua_recover_tune' : args[0]);
  await outDir.create(recursive: true);
  final pairs = await _loadPairs();
  final processor = const UnderwaterProcessor();
  final stage1 = _scoreTop(
    _expandColor(RestorationPreset.auto.settings),
    pairs,
    processor,
    keep: 8,
  );
  await _writeScores(outDir, 'stage1_color', stage1);
  final stage2 = _scoreTop(
    stage1.expand((seed) => _expandTone(seed.settings)),
    pairs,
    processor,
    keep: 8,
  );
  await _writeScores(outDir, 'stage2_tone', stage2);
  final scored = _scoreTop(
    stage2.expand((seed) => _expandLight(seed.settings)),
    pairs,
    processor,
    keep: 8,
  );
  final log = StringBuffer();
  for (var i = 0; i < math.min(24, scored.length); i++) {
    final item = scored[i];
    log.writeln(
      '${i + 1}. score=${item.score.toStringAsFixed(3)} ${_settingsLine(item.settings)}',
    );
  }
  stdout.write(log);
  await File(p.join(outDir.path, 'scores.txt')).writeAsString(log.toString());
  await _writeBestSheets(outDir, pairs, processor, scored.take(8).toList());
}

Future<List<_Pair>> _loadPairs() async {
  final pairs = <_Pair>[];
  for (final i in _referencePairIndices()) {
    final before = img.decodeImage(
      await File('test/img/before$i.webp').readAsBytes(),
    );
    final after = img.decodeImage(
      await File('test/img/after$i.webp').readAsBytes(),
    );
    if (before == null || after == null) continue;
    final resizedBefore = _fit(before, 96, 72);
    final resizedAfter = img.copyResize(
      after,
      width: resizedBefore.width,
      height: resizedBefore.height,
      interpolation: img.Interpolation.linear,
    );
    pairs.add(_Pair(i, resizedBefore, resizedAfter));
  }
  if (pairs.isEmpty) throw StateError('No reference pairs found in test/img.');
  return pairs;
}

List<int> _referencePairIndices() {
  final fixtureDirectory = Directory('test/img');
  if (!fixtureDirectory.existsSync()) return const [];
  final beforePattern = RegExp(r'^before(\d+)\.webp$');
  final afterPattern = RegExp(r'^after(\d+)\.webp$');
  final before = <int>{};
  final after = <int>{};
  for (final file in fixtureDirectory.listSync().whereType<File>()) {
    final name = p.basename(file.path);
    final beforeMatch = beforePattern.firstMatch(name);
    if (beforeMatch != null) {
      before.add(int.parse(beforeMatch.group(1)!));
      continue;
    }
    final afterMatch = afterPattern.firstMatch(name);
    if (afterMatch != null) after.add(int.parse(afterMatch.group(1)!));
  }
  return before.intersection(after).toList()..sort();
}

List<RestorationSettings> _expandColor(RestorationSettings base) {
  final candidates = <RestorationSettings>[];
  const recoveries = [0.96, 1.04, 1.08, 1.12, 1.18];
  const redRecoveries = [1.24, 1.34, 1.42, 1.52, 1.64];
  const autoWhiteBalances = [0.76, 0.84, 0.90, 0.96, 1.00];
  const contrastStretches = [0.46, 0.52, 0.58, 0.64, 0.72];
  for (final recovery in recoveries) {
    for (final redRecovery in redRecoveries) {
      for (final autoWhiteBalance in autoWhiteBalances) {
        for (final contrastStretch in contrastStretches) {
          candidates.add(
            base.asPro(
              recovery: recovery,
              redRecovery: redRecovery,
              autoWhiteBalance: autoWhiteBalance,
              contrastStretch: contrastStretch,
            ),
          );
        }
      }
    }
  }
  return _dedupe(candidates);
}

List<RestorationSettings> _expandTone(RestorationSettings base) {
  final candidates = <RestorationSettings>[base];
  const contrasts = [1.00, 1.04, 1.08, 1.12];
  const gammas = [0.94, 0.98, 1.02];
  const saturations = [0.88, 0.96, 1.04, 1.12];
  const vibrances = [0.0, 0.06];
  const hazeReductions = [0.06, 0.14];
  for (final contrast in contrasts) {
    for (final gamma in gammas) {
      for (final saturation in saturations) {
        for (final vibrance in vibrances) {
          for (final hazeReduction in hazeReductions) {
            candidates.add(
              base.asPro(
                contrast: contrast,
                gamma: gamma,
                saturation: saturation,
                vibrance: vibrance,
                hazeReduction: hazeReduction,
              ),
            );
          }
        }
      }
    }
  }
  return _dedupe(candidates);
}

List<RestorationSettings> _expandLight(RestorationSettings base) {
  final candidates = <RestorationSettings>[base];
  const shadows = [-0.04, 0.0, 0.04, 0.08];
  const highlights = [-0.12, -0.06, 0.0, 0.04];
  const exposures = [-0.04, 0.0, 0.04, 0.08];
  const blackPoints = [0.0, 0.02];
  for (final exposure in exposures) {
    for (final shadowsValue in shadows) {
      for (final highlightsValue in highlights) {
        for (final blackPoint in blackPoints) {
          candidates.add(
            base.asPro(
              exposure: exposure,
              shadows: shadowsValue,
              highlights: highlightsValue,
              blackPoint: blackPoint,
            ),
          );
        }
      }
    }
  }
  return _dedupe(candidates);
}

List<RestorationSettings> _dedupe(Iterable<RestorationSettings> candidates) {
  final byKey = <String, RestorationSettings>{};
  for (final candidate in candidates) {
    byKey[_settingsLine(candidate)] = candidate;
  }
  return byKey.values.toList();
}

List<_Scored> _scoreTop(
  Iterable<RestorationSettings> candidates,
  List<_Pair> pairs,
  UnderwaterProcessor processor, {
  required int keep,
}) {
  final scored = <_Scored>[];
  for (final settings in _dedupe(candidates)) {
    scored.add(_Scored(settings, _scoreSettings(settings, pairs, processor)));
  }
  scored.sort((a, b) => a.score.compareTo(b.score));
  return scored.take(keep).toList();
}

double _scoreSettings(
  RestorationSettings settings,
  List<_Pair> pairs,
  UnderwaterProcessor processor,
) {
  var score = 0.0;
  for (final pair in pairs) {
    final output = processor.restoreImage(pair.before.clone(), settings);
    score += _score(output, pair.after);
  }
  return score / pairs.length;
}

Future<void> _writeScores(
  Directory outDir,
  String name,
  List<_Scored> scored,
) async {
  final log = StringBuffer();
  for (var i = 0; i < scored.length; i++) {
    final item = scored[i];
    log.writeln(
      '${i + 1}. score=${item.score.toStringAsFixed(3)} ${_settingsLine(item.settings)}',
    );
  }
  await File(p.join(outDir.path, '$name.txt')).writeAsString(log.toString());
}

double _score(img.Image output, img.Image target) {
  final color = _meanAbsDelta(output, target);
  final outStats = _Stats.from(output);
  final targetStats = _Stats.from(target);
  final ratioPenalty =
      (outStats.rg - targetStats.rg).abs() * 6.0 +
      (outStats.bg - targetStats.bg).abs() * 6.0;
  final lumaPenalty =
      (outStats.p10 - targetStats.p10).abs() * 0.03 +
      (outStats.p50 - targetStats.p50).abs() * 0.06 +
      (outStats.p90 - targetStats.p90).abs() * 0.04;
  final satPenalty = (outStats.sat - targetStats.sat).abs() * 5.0;
  return color + ratioPenalty + lumaPenalty + satPenalty;
}

Future<void> _writeBestSheets(
  Directory outDir,
  List<_Pair> pairs,
  UnderwaterProcessor processor,
  List<_Scored> best,
) async {
  for (var candidateIndex = 0; candidateIndex < best.length; candidateIndex++) {
    final candidate = best[candidateIndex];
    final rows = <img.Image>[];
    for (var pairIndex = 0; pairIndex < pairs.length; pairIndex++) {
      final pair = pairs[pairIndex];
      final output = processor.restoreImage(
        pair.before.clone(),
        candidate.settings,
      );
      final row = img.Image(
        width: pair.before.width * 3,
        height: pair.before.height + 54,
      );
      img.fill(row, color: img.ColorRgb8(18, 20, 24));
      _pasteLabeled(row, pair.before, 0, 'reference ${pair.index}', 'Before');
      _pasteLabeled(
        row,
        output,
        pair.before.width,
        'score ${candidate.score.toStringAsFixed(2)}',
        'Candidate ${candidateIndex + 1}',
      );
      _pasteLabeled(
        row,
        pair.after,
        pair.before.width * 2,
        'reference ${pair.index}',
        'Target after',
      );
      rows.add(row);
      await File(
        p.join(
          outDir.path,
          'candidate_${candidateIndex + 1}_ref_${pair.index}.jpg',
        ),
      ).writeAsBytes(img.encodeJpg(output, quality: 92));
    }
    final sheet = img.Image(
      width: rows.first.width,
      height: rows.fold(0, (sum, row) => sum + row.height),
    );
    img.fill(sheet, color: img.ColorRgb8(18, 20, 24));
    var y = 0;
    for (final row in rows) {
      img.compositeImage(sheet, row, dstY: y);
      y += row.height;
    }
    await File(
      p.join(outDir.path, 'candidate_${candidateIndex + 1}_sheet.jpg'),
    ).writeAsBytes(img.encodeJpg(sheet, quality: 92));
  }
}

img.Image _fit(img.Image source, int maxWidth, int maxHeight) {
  final scale = math.min(maxWidth / source.width, maxHeight / source.height);
  return img.copyResize(
    source,
    width: math.max(1, (source.width * scale).round()),
    height: math.max(1, (source.height * scale).round()),
    interpolation: img.Interpolation.linear,
  );
}

void _pasteLabeled(
  img.Image dst,
  img.Image src,
  int x,
  String file,
  String label,
) {
  img.compositeImage(dst, src, dstX: x, dstY: 54);
  img.drawString(
    dst,
    label,
    font: img.arial24,
    x: x + 10,
    y: 8,
    color: img.ColorRgb8(245, 246, 248),
  );
  img.drawString(
    dst,
    file,
    font: img.arial14,
    x: x + 10,
    y: 34,
    color: img.ColorRgb8(190, 196, 205),
  );
}

double _meanAbsDelta(img.Image a, img.Image b) {
  final width = math.min(a.width, b.width);
  final height = math.min(a.height, b.height);
  var sum = 0.0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final pa = a.getPixel(x, y);
      final pb = b.getPixel(x, y);
      sum += (pa.r - pb.r).abs();
      sum += (pa.g - pb.g).abs();
      sum += (pa.b - pb.b).abs();
    }
  }
  return sum / (width * height * 3);
}

String _settingsLine(RestorationSettings s) =>
    'rec=${s.recovery.toStringAsFixed(2)} red=${s.redRecovery.toStringAsFixed(2)} awb=${s.autoWhiteBalance.toStringAsFixed(2)} stretch=${s.contrastStretch.toStringAsFixed(2)} ctr=${s.contrast.toStringAsFixed(2)} gamma=${s.gamma.toStringAsFixed(2)} sat=${s.saturation.toStringAsFixed(2)} vib=${s.vibrance.toStringAsFixed(2)} haze=${s.hazeReduction.toStringAsFixed(2)} exp=${s.exposure.toStringAsFixed(2)} sh=${s.shadows.toStringAsFixed(2)} hi=${s.highlights.toStringAsFixed(2)} bp=${s.blackPoint.toStringAsFixed(2)}';

class _Pair {
  const _Pair(this.index, this.before, this.after);
  final int index;
  final img.Image before;
  final img.Image after;
}

class _Scored {
  const _Scored(this.settings, this.score);
  final RestorationSettings settings;
  final double score;
}

class _Stats {
  const _Stats({
    required this.rg,
    required this.bg,
    required this.sat,
    required this.p10,
    required this.p50,
    required this.p90,
  });

  final double rg;
  final double bg;
  final double sat;
  final int p10;
  final int p50;
  final int p90;

  factory _Stats.from(img.Image image) {
    var r = 0.0, g = 0.0, b = 0.0, sat = 0.0;
    final hist = List<int>.filled(256, 0);
    final n = image.width * image.height;
    for (final px in image) {
      r += px.r;
      g += px.g;
      b += px.b;
      final maxChannel = math.max(px.r, math.max(px.g, px.b)).toDouble();
      final minChannel = math.min(px.r, math.min(px.g, px.b)).toDouble();
      sat += maxChannel == 0 ? 0 : (maxChannel - minChannel) / maxChannel;
      final luma = (0.2126 * px.r + 0.7152 * px.g + 0.0722 * px.b)
          .round()
          .clamp(0, 255)
          .toInt();
      hist[luma]++;
    }
    r /= n;
    g /= n;
    b /= n;
    return _Stats(
      rg: r / math.max(g, 0.001),
      bg: b / math.max(g, 0.001),
      sat: sat / n,
      p10: _percentile(hist, n, .10),
      p50: _percentile(hist, n, .50),
      p90: _percentile(hist, n, .90),
    );
  }
}

int _percentile(List<int> hist, int total, double p) {
  final target = math.max(1, (total * p).round()).toInt();
  var running = 0;
  for (var i = 0; i < hist.length; i++) {
    running += hist[i];
    if (running >= target) return i;
  }
  return hist.length - 1;
}
