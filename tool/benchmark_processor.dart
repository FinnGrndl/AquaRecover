import 'dart:io';
import 'dart:math' as math;

import 'package:aqua_recover/core/models/restoration_settings.dart';
import 'package:aqua_recover/core/processing/underwater_processor.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final maxDimension = args.isEmpty ? 1280 : int.parse(args.first);
  final quality = args.length > 1 && args[1] == 'preview'
      ? RestorationRenderQuality.preview
      : RestorationRenderQuality.export;
  final inputs = Directory('test/img').listSync().whereType<File>().where((
    file,
  ) {
    final ext = p.extension(file.path).toLowerCase();
    return ext == '.jpg' || ext == '.jpeg' || ext == '.webp';
  }).toList()..sort((a, b) => a.path.compareTo(b.path));
  final processor = const UnderwaterProcessor();
  var totalPixels = 0;
  var totalElapsed = Duration.zero;

  for (final file in inputs) {
    final decoded = img.decodeImage(await file.readAsBytes());
    if (decoded == null) continue;
    final source = _fit(decoded, maxDimension);
    processor.restoreImage(
      source.clone(),
      RestorationPreset.auto.settings,
      quality: quality,
    );
    final watch = Stopwatch()..start();
    processor.restoreImage(
      source.clone(),
      RestorationPreset.auto.settings,
      quality: quality,
    );
    watch.stop();
    final pixels = source.width * source.height;
    totalPixels += pixels;
    totalElapsed += watch.elapsed;
    stdout.writeln(
      '${p.basename(file.path).padRight(46)} '
      '${source.width}x${source.height} '
      '${watch.elapsedMilliseconds.toString().padLeft(5)} ms '
      '${(pixels / watch.elapsedMicroseconds).toStringAsFixed(2)} MP/s',
    );
  }

  if (totalPixels == 0) return;
  stdout.writeln(
    '${'Total'.padRight(46)}'
    '${' '.padRight(10)}'
    '${totalElapsed.inMilliseconds.toString().padLeft(5)} ms '
    '${(totalPixels / totalElapsed.inMicroseconds).toStringAsFixed(2)} MP/s',
  );
}

img.Image _fit(img.Image source, int maxDimension) {
  final maxSide = math.max(source.width, source.height);
  if (maxSide <= maxDimension) return source;
  final scale = maxDimension / maxSide;
  return img.copyResize(
    source,
    width: math.max(1, (source.width * scale).round()),
    height: math.max(1, (source.height * scale).round()),
    interpolation: img.Interpolation.linear,
  );
}
