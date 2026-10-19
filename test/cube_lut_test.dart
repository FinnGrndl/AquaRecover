import 'dart:io';

import 'package:aqua_recover/core/processing/lut_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Writes a `.cube` file for [f], storing samples red-fastest as the format
/// requires.
Future<String> _writeCube(
  Directory dir,
  int size,
  List<double> Function(double r, double g, double b) f,
) async {
  final buffer = StringBuffer('TITLE "test"\nLUT_3D_SIZE $size\n');
  for (var b = 0; b < size; b++) {
    for (var g = 0; g < size; g++) {
      for (var r = 0; r < size; r++) {
        final out = f(r / (size - 1), g / (size - 1), b / (size - 1));
        buffer.writeln(out.map((v) => v.toStringAsFixed(6)).join(' '));
      }
    }
  }
  final file = File('${dir.path}/test.cube');
  await file.writeAsString(buffer.toString());
  return file.path;
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('aquarecover_cube');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('reads samples with red changing fastest', () async {
    // An asymmetric map: swapping the red and blue axes would change it.
    final path = await _writeCube(dir, 2, (r, g, b) => [r, g * 0.5, 1 - b]);
    final cube = await CubeLut.read(path);
    final source = img.Image(width: 1, height: 1, numChannels: 4)
      ..setPixelRgba(0, 0, 200, 50, 30, 77);
    final pixel = cube.apply(source, 1).getPixel(0, 0);
    expect(pixel.r, closeTo(200, 1));
    expect(pixel.g, closeTo(25, 1));
    expect(pixel.b, closeTo(225, 1));
    expect(pixel.a, 77);
  });

  test('intensity blends toward the original', () async {
    final path = await _writeCube(dir, 3, (r, g, b) => [1 - r, 1 - g, 1 - b]);
    final cube = await CubeLut.read(path);
    final source = img.Image(width: 2, height: 1)
      ..setPixelRgb(0, 0, 0, 128, 255)
      ..setPixelRgb(1, 0, 40, 40, 40);
    final half = cube.apply(source, 0.5);
    expect(half.getPixel(0, 0).r, closeTo(128, 1));
    expect(half.getPixel(0, 0).b, closeTo(128, 1));
    final none = cube.apply(source, 0);
    expect(none.getPixel(1, 0).r, 40);
  });

  test('rejects a cube with the wrong sample count', () async {
    final file = File('${dir.path}/short.cube');
    await file.writeAsString('LUT_3D_SIZE 2\n0 0 0\n1 1 1\n');
    expect(CubeLut.read(file.path), throwsFormatException);
  });
}
