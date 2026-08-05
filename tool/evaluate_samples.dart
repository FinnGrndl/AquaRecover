import 'dart:io';
import 'dart:math' as math;

import 'package:aqua_recover/core/models/lut_profile.dart';
import 'package:aqua_recover/core/models/restoration_settings.dart';
import 'package:aqua_recover/core/processing/lut_service.dart';
import 'package:aqua_recover/core/processing/underwater_processor.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final fixtureDirectory = Directory('test/img');
  if (!fixtureDirectory.existsSync()) {
    stderr.writeln(
      'No local test media found in test/img. See docs/LOCAL_TEST_MEDIA.md.',
    );
    exitCode = 2;
    return;
  }
  final outDir = Directory(
    args.isEmpty ? '/tmp/aqua_recover_samples' : args[0],
  );
  await outDir.create(recursive: true);
  final inputs =
      fixtureDirectory
          .listSync()
          .whereType<File>()
          .where((file) => p.extension(file.path).toLowerCase() == '.jpg')
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final processor = const UnderwaterProcessor();
  final lut = const LutService();
  final rows = <img.Image>[];
  for (final file in inputs) {
    final decoded = img.decodeImage(await file.readAsBytes());
    if (decoded == null) continue;
    final original = _fit(decoded, 420, 280);
    final auto = await lut.apply(
      processor.restoreImage(original.clone(), RestorationPreset.auto.settings),
      LutProfile.none,
    );
    final vivid = await lut.apply(
      processor.restoreImage(
        original.clone(),
        RestorationPreset.vivid.settings,
      ),
      LutProfile.none,
    );
    final deep = await lut.apply(
      processor.restoreImage(original.clone(), RestorationPreset.deep.settings),
      LutProfile.none,
    );
    final row = img.Image(
      width: original.width * 4,
      height: original.height + 54,
    );
    img.fill(row, color: img.ColorRgb8(18, 20, 24));
    _pasteLabeled(row, original, 0, p.basename(file.path), 'Original');
    _pasteLabeled(row, auto, original.width, p.basename(file.path), 'Auto');
    _pasteLabeled(
      row,
      vivid,
      original.width * 2,
      p.basename(file.path),
      'Vivid',
    );
    _pasteLabeled(row, deep, original.width * 3, p.basename(file.path), 'Deep');
    rows.add(row);
    await File(
      p.join(outDir.path, '${p.basenameWithoutExtension(file.path)}_auto.jpg'),
    ).writeAsBytes(img.encodeJpg(auto, quality: 92));
    await File(
      p.join(outDir.path, '${p.basenameWithoutExtension(file.path)}_vivid.jpg'),
    ).writeAsBytes(img.encodeJpg(vivid, quality: 92));
    await File(
      p.join(outDir.path, '${p.basenameWithoutExtension(file.path)}_deep.jpg'),
    ).writeAsBytes(img.encodeJpg(deep, quality: 92));
    stdout.writeln(p.basename(file.path));
    stdout.writeln('  original ${_stats(original)}');
    stdout.writeln('  auto     ${_stats(auto)}');
    stdout.writeln('  vivid    ${_stats(vivid)}');
    stdout.writeln('  deep     ${_stats(deep)}');
  }

  if (rows.isNotEmpty) {
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
    final sheetPath = p.join(outDir.path, 'comparison_sheet.jpg');
    await File(sheetPath).writeAsBytes(img.encodeJpg(sheet, quality: 92));
    stdout.writeln('Wrote $sheetPath');
  }
  await _evaluateReferencePairs(outDir, processor, lut);
  await _evaluateVideo(outDir);
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

String _stats(img.Image image) {
  var r = 0.0, g = 0.0, b = 0.0, sat = 0.0;
  final histLuma = List<int>.filled(256, 0);
  final n = image.width * image.height;
  for (final px in image) {
    final pr = px.r / 255.0;
    final pg = px.g / 255.0;
    final pb = px.b / 255.0;
    r += pr;
    g += pg;
    b += pb;
    final maxC = math.max(pr, math.max(pg, pb));
    final minC = math.min(pr, math.min(pg, pb));
    sat += maxC <= 0 ? 0 : (maxC - minC) / maxC;
    final luma = (0.2126 * px.r + 0.7152 * px.g + 0.0722 * px.b)
        .round()
        .clamp(0, 255)
        .toInt();
    histLuma[luma]++;
  }
  r /= n;
  g /= n;
  b /= n;
  sat /= n;
  return 'rgb=(${(r * 255).round()}, ${(g * 255).round()}, ${(b * 255).round()}) sat=${sat.toStringAsFixed(2)} r/g=${(r / math.max(g, .001)).toStringAsFixed(2)} b/g=${(b / math.max(g, .001)).toStringAsFixed(2)} luma=${_percentile(histLuma, n, .10)}/${_percentile(histLuma, n, .50)}/${_percentile(histLuma, n, .90)}';
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

double _meanAbsDelta(img.Image a, img.Image b) {
  final width = math.min(a.width, b.width);
  final height = math.min(a.height, b.height);
  if (width == 0 || height == 0) return 0;
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

Future<void> _evaluateVideo(Directory outDir) async {
  final input = File('test/img/SportDiver_20260427_063800.MOV');
  if (!input.existsSync()) return;
  final originalPath = p.join(outDir.path, 'video_frame_original.jpg');
  final restoredPath = p.join(outDir.path, 'video_frame_auto.jpg');
  await _runFfmpeg([
    '-hide_banner',
    '-y',
    '-ss',
    '3',
    '-i',
    input.path,
    '-frames:v',
    '1',
    '-vf',
    'scale=420:-1',
    '-q:v',
    '2',
    originalPath,
  ]);
  await _runFfmpeg([
    '-hide_banner',
    '-y',
    '-ss',
    '3',
    '-i',
    input.path,
    '-frames:v',
    '1',
    '-vf',
    '${RestorationPreset.auto.settings.ffmpegFilter},scale=420:-1',
    '-q:v',
    '2',
    restoredPath,
  ]);
  final original = img.decodeImage(await File(originalPath).readAsBytes());
  final restored = img.decodeImage(await File(restoredPath).readAsBytes());
  if (original == null || restored == null) return;
  final row = img.Image(
    width: original.width * 2,
    height: original.height + 54,
  );
  img.fill(row, color: img.ColorRgb8(18, 20, 24));
  _pasteLabeled(row, original, 0, p.basename(input.path), 'Video original');
  _pasteLabeled(
    row,
    restored,
    original.width,
    p.basename(input.path),
    'Video auto',
  );
  final videoSheet = p.join(outDir.path, 'video_frame_comparison.jpg');
  await File(videoSheet).writeAsBytes(img.encodeJpg(row, quality: 92));
  stdout.writeln('Video original ${_stats(original)}');
  stdout.writeln('Video auto     ${_stats(restored)}');
  stdout.writeln('Wrote $videoSheet');
}

Future<void> _evaluateReferencePairs(
  Directory outDir,
  UnderwaterProcessor processor,
  LutService lut,
) async {
  final rows = <img.Image>[];
  final tuned = RestorationPreset.auto.settings;
  for (final i in _referencePairIndices()) {
    final beforeFile = File('test/img/before$i.webp');
    final afterFile = File('test/img/after$i.webp');

    final before = img.decodeImage(await beforeFile.readAsBytes());
    final target = img.decodeImage(await afterFile.readAsBytes());
    if (before == null || target == null) continue;

    final fittedBefore = _fit(before, 360, 270);
    final fittedTarget = img.copyResize(
      target,
      width: fittedBefore.width,
      height: fittedBefore.height,
      interpolation: img.Interpolation.linear,
    );
    final auto = await lut.apply(
      processor.restoreImage(fittedBefore.clone(), tuned),
      LutProfile.none,
    );
    final vivid = await lut.apply(
      processor.restoreImage(
        fittedBefore.clone(),
        RestorationPreset.vivid.settings,
      ),
      LutProfile.none,
    );

    final row = img.Image(
      width: fittedBefore.width * 4,
      height: fittedBefore.height + 54,
    );
    img.fill(row, color: img.ColorRgb8(18, 20, 24));
    _pasteLabeled(row, fittedBefore, 0, 'reference $i', 'Before');
    _pasteLabeled(row, auto, fittedBefore.width, 'reference $i', 'Aqua Auto');
    _pasteLabeled(
      row,
      vivid,
      fittedBefore.width * 2,
      'reference $i',
      'Aqua Vivid',
    );
    _pasteLabeled(
      row,
      fittedTarget,
      fittedBefore.width * 3,
      'reference $i',
      'Target after',
    );
    rows.add(row);

    await File(
      p.join(outDir.path, 'reference_${i}_auto.jpg'),
    ).writeAsBytes(img.encodeJpg(auto, quality: 92));
    final beforeDelta = _meanAbsDelta(fittedBefore, fittedTarget);
    stdout.writeln('Reference $i');
    stdout.writeln('  before ${_stats(fittedBefore)}');
    stdout.writeln('  target ${_stats(fittedTarget)}');
    stdout.writeln('  before delta=${beforeDelta.toStringAsFixed(2)}');
    stdout.writeln(
      '  auto   ${_stats(auto)} delta=${_meanAbsDelta(auto, fittedTarget).toStringAsFixed(2)}',
    );
    stdout.writeln(
      '  vivid  ${_stats(vivid)} delta=${_meanAbsDelta(vivid, fittedTarget).toStringAsFixed(2)}',
    );
  }

  if (rows.isEmpty) return;
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
  final path = p.join(outDir.path, 'reference_pairs_sheet.jpg');
  await File(path).writeAsBytes(img.encodeJpg(sheet, quality: 92));
  stdout.writeln('Wrote $path');
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

Future<void> _runFfmpeg(List<String> args) async {
  final result = await Process.run('/opt/homebrew/bin/ffmpeg', args);
  if (result.exitCode != 0) {
    throw StateError('ffmpeg failed: ${result.stderr}');
  }
}
