import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/lut_profile.dart';

class LutService {
  const LutService();

  Future<img.Image> apply(img.Image source, LutProfile profile) async {
    if (!profile.isEnabled) return source;
    return switch (profile.kind) {
      LutKind.none => source,
      LutKind.coralWarm => _applyRecipe(
        source,
        profile.intensity,
        const _Recipe(1.08, 1.02, .94, 1.08, 1.03),
      ),
      LutKind.blueWater => _applyRecipe(
        source,
        profile.intensity,
        const _Recipe(1.02, 1.01, 1.05, 1.04, 1.05),
      ),
      LutKind.greenWater => _applyRecipe(
        source,
        profile.intensity,
        const _Recipe(1.10, .96, 1.05, 1.06, 1.04),
      ),
      LutKind.customCube => await _applyCube(source, profile),
    };
  }

  Future<img.Image> _applyCube(img.Image source, LutProfile profile) async {
    final path = profile.path;
    if (path == null) return source;
    final cube = await CubeLut.read(path);
    return cube.apply(source, profile.intensity);
  }

  static List<String> videoFiltersFor(LutProfile profile) {
    if (!profile.isEnabled) return const [];
    final t = profile.intensity.clamp(0.0, 1.0).toDouble();
    String f(num value) => (value * t).toStringAsFixed(3);
    String eq({required double saturation, required double contrast}) =>
        'eq=saturation=${(1.0 + (saturation - 1.0) * t).toStringAsFixed(3)}:contrast=${(1.0 + (contrast - 1.0) * t).toStringAsFixed(3)}';
    return switch (profile.kind) {
      LutKind.none => const [],
      LutKind.coralWarm => [
        'colorbalance=rs=${f(.030)}:rm=${f(.020)}:rh=${f(.010)}:bs=${f(-.015)}:bm=${f(-.010)}:bh=0.000',
        eq(saturation: 1.050, contrast: 1.020),
      ],
      LutKind.blueWater => [
        'colorbalance=bs=${f(.010)}:bm=${f(.010)}:bh=${f(.015)}',
        eq(saturation: 1.030, contrast: 1.030),
      ],
      LutKind.greenWater => [
        'colorbalance=rs=${f(.030)}:rm=${f(.020)}:rh=${f(.015)}:gs=${f(-.020)}:gm=${f(-.018)}:gh=${f(-.010)}',
        eq(saturation: 1.040, contrast: 1.025),
      ],
      LutKind.customCube =>
        profile.path == null
            ? const []
            : ['lut3d=file=${_escapeFilterPath(profile.path!)}:interp=tetrahedral'],
    };
  }

  static String _escapeFilterPath(String path) {
    final escaped = path
        .replaceAll('\\', '\\\\')
        .replaceAll("'", r"\'")
        .replaceAll(':', r'\:');
    return "'$escaped'";
  }

  static img.Image _applyRecipe(
    img.Image source,
    double intensity,
    _Recipe recipe,
  ) {
    final amount = intensity.clamp(0.0, 1.0).toDouble();
    return _mapRgb(source, (data, i) {
      final originalR = data[i].toDouble();
      final originalG = data[i + 1].toDouble();
      final originalB = data[i + 2].toDouble();
      var r = (originalR * recipe.red - 128) * recipe.contrast + 128;
      var g = (originalG * recipe.green - 128) * recipe.contrast + 128;
      var b = (originalB * recipe.blue - 128) * recipe.contrast + 128;
      final luma = .2126 * r + .7152 * g + .0722 * b;
      r = luma + (r - luma) * recipe.saturation;
      g = luma + (g - luma) * recipe.saturation;
      b = luma + (b - luma) * recipe.saturation;
      data[i] = _byte(_mix(originalR, r, amount));
      data[i + 1] = _byte(_mix(originalG, g, amount));
      data[i + 2] = _byte(_mix(originalB, b, amount));
    });
  }

  /// Copies [source] into an 8-bit RGB(A) image and runs [mapPixel] on each
  /// pixel's red byte offset in the packed buffer. This avoids the per-pixel
  /// `getPixel`/`setPixelRgba` object traffic of the generic accessors.
  static img.Image _mapRgb(
    img.Image source,
    void Function(Uint8List data, int offset) mapPixel,
  ) {
    final packed =
        source.format == img.Format.uint8 &&
            source.numChannels >= 3 &&
            !source.hasPalette
        ? source.clone()
        : source.convert(format: img.Format.uint8, numChannels: 4);
    final data = packed.data!.toUint8List();
    final stride = packed.numChannels;
    for (var i = 0; i + 2 < data.length; i += stride) {
      mapPixel(data, i);
    }
    return packed;
  }

  static double _mix(double a, double b, double t) => a + (b - a) * t;
  static int _byte(double v) => v.round().clamp(0, 255).toInt();
}

class CubeLut {
  const CubeLut._({required this.size, required Float32List table})
    : _table = table;
  final int size;

  /// Packed RGB samples in file order (red changes fastest).
  final Float32List _table;

  static Future<CubeLut> read(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('LUT file not found.', path);
    }
    if (await file.length() > 8 * 1024 * 1024) {
      throw StateError('LUT file is too large. Maximum is 8 MB.');
    }
    final lines = await file.readAsLines();
    var size = 0;
    final values = <double>[];
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final upper = line.toUpperCase();
      if (upper.startsWith('TITLE') ||
          upper.startsWith('DOMAIN_MIN') ||
          upper.startsWith('DOMAIN_MAX')) {
        continue;
      }
      if (upper.startsWith('LUT_3D_SIZE')) {
        final parts = line.split(RegExp(r'\s+'));
        size = int.parse(parts[1]);
        if (size < 2 || size > 65) {
          throw const FormatException(
            'Only 3D LUT sizes from 2 to 65 are supported.',
          );
        }
        continue;
      }
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 3) {
        values
          ..add(double.parse(parts[0]))
          ..add(double.parse(parts[1]))
          ..add(double.parse(parts[2]));
      }
    }
    if (size == 0) {
      throw const FormatException('Missing LUT_3D_SIZE in .cube file.');
    }
    final expected = size * size * size;
    if (values.length != expected * 3) {
      throw FormatException(
        'Expected $expected LUT samples, found ${values.length ~/ 3}.',
      );
    }
    return CubeLut._(size: size, table: Float32List.fromList(values));
  }

  img.Image apply(img.Image source, double intensity) {
    final amount = intensity.clamp(0.0, 1.0).toDouble();
    final maxIndex = size - 1;
    // Per-byte lattice coordinates, shared by all three channels.
    final lower = Int32List(256);
    final upper = Int32List(256);
    final fraction = Float64List(256);
    for (var v = 0; v < 256; v++) {
      final f = v / 255.0 * maxIndex;
      final i0 = math.min(f.floor(), maxIndex);
      lower[v] = i0;
      upper[v] = math.min(i0 + 1, maxIndex);
      fraction[v] = f - i0;
    }
    final table = _table;
    final plane = size * size;
    return LutService._mapRgb(source, (data, i) {
      final sr = data[i];
      final sg = data[i + 1];
      final sb = data[i + 2];
      final fr = fraction[sr];
      final fg = fraction[sg];
      final fb = fraction[sb];
      // `.cube` stores red fastest, then green, then blue.
      final r0 = lower[sr], r1 = upper[sr];
      final g0 = lower[sg] * size, g1 = upper[sg] * size;
      final b0 = lower[sb] * plane, b1 = upper[sb] * plane;
      final i000 = (b0 + g0 + r0) * 3, i100 = (b0 + g0 + r1) * 3;
      final i010 = (b0 + g1 + r0) * 3, i110 = (b0 + g1 + r1) * 3;
      final i001 = (b1 + g0 + r0) * 3, i101 = (b1 + g0 + r1) * 3;
      final i011 = (b1 + g1 + r0) * 3, i111 = (b1 + g1 + r1) * 3;
      for (var c = 0; c < 3; c++) {
        final c00 = _mix(table[i000 + c], table[i100 + c], fr);
        final c10 = _mix(table[i010 + c], table[i110 + c], fr);
        final c01 = _mix(table[i001 + c], table[i101 + c], fr);
        final c11 = _mix(table[i011 + c], table[i111 + c], fr);
        final mapped = _mix(_mix(c00, c10, fg), _mix(c01, c11, fg), fb);
        final original = data[i + c].toDouble();
        data[i + c] = _byte(_mix(original, mapped * 255, amount));
      }
    });
  }

  static double _mix(double a, double b, double t) => a + (b - a) * t;
  static int _byte(double v) => v.round().clamp(0, 255).toInt();
}

class _Recipe {
  const _Recipe(
    this.red,
    this.green,
    this.blue,
    this.saturation,
    this.contrast,
  );
  final double red;
  final double green;
  final double blue;
  final double saturation;
  final double contrast;
}
