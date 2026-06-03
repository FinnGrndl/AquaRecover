import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../models/lut_profile.dart';

class LutService {
  const LutService();

  Future<img.Image> apply(img.Image source, LutProfile profile) async {
    if (!profile.isEnabled) return source;
    return switch (profile.kind) {
      LutKind.none => source,
      LutKind.coralWarm => _applyRecipe(source, profile.intensity, const _Recipe(1.08, 1.02, .94, 1.08, 1.03)),
      LutKind.blueWater => _applyRecipe(source, profile.intensity, const _Recipe(1.02, 1.01, 1.05, 1.04, 1.05)),
      LutKind.greenWater => _applyRecipe(source, profile.intensity, const _Recipe(1.10, .96, 1.05, 1.06, 1.04)),
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
    String eq({required double saturation, required double contrast}) => 'eq=saturation=${(1.0 + (saturation - 1.0) * t).toStringAsFixed(3)}:contrast=${(1.0 + (contrast - 1.0) * t).toStringAsFixed(3)}';
    return switch (profile.kind) {
      LutKind.none => const [],
      LutKind.coralWarm => ['colorbalance=rs=${f(.030)}:rm=${f(.020)}:rh=${f(.010)}:bs=${f(-.015)}:bm=${f(-.010)}:bh=0.000', eq(saturation: 1.050, contrast: 1.020)],
      LutKind.blueWater => ['colorbalance=bs=${f(.010)}:bm=${f(.010)}:bh=${f(.015)}', eq(saturation: 1.030, contrast: 1.030)],
      LutKind.greenWater => ['colorbalance=rs=${f(.030)}:rm=${f(.020)}:rh=${f(.015)}:gs=${f(-.020)}:gm=${f(-.018)}:gh=${f(-.010)}', eq(saturation: 1.040, contrast: 1.025)],
      LutKind.customCube => profile.path == null ? const [] : ['lut3d=file=${_escapeFilterPath(profile.path!)}:interp=tetrahedral'],
    };
  }

  static String _escapeFilterPath(String path) {
    final escaped = path
        .replaceAll('\\', '\\\\')
        .replaceAll("'", r"\'")
        .replaceAll(':', r'\:');
    return "'$escaped'";
  }

  static img.Image _applyRecipe(img.Image source, double intensity, _Recipe recipe) {
    final out = source.clone();
    final amount = intensity.clamp(0.0, 1.0).toDouble();
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        final p = source.getPixel(x, y);
        final originalR = p.r.toDouble();
        final originalG = p.g.toDouble();
        final originalB = p.b.toDouble();
        var r = (originalR * recipe.red - 128) * recipe.contrast + 128;
        var g = (originalG * recipe.green - 128) * recipe.contrast + 128;
        var b = (originalB * recipe.blue - 128) * recipe.contrast + 128;
        final luma = .2126 * r + .7152 * g + .0722 * b;
        r = luma + (r - luma) * recipe.saturation;
        g = luma + (g - luma) * recipe.saturation;
        b = luma + (b - luma) * recipe.saturation;
        out.setPixelRgba(x, y, _byte(_mix(originalR, r, amount)), _byte(_mix(originalG, g, amount)), _byte(_mix(originalB, b, amount)), p.a.toInt());
      }
    }
    return out;
  }

  static double _mix(double a, double b, double t) => a + (b - a) * t;
  static int _byte(double v) => v.round().clamp(0, 255).toInt();
}

class CubeLut {
  const CubeLut._({required this.size, required List<_Rgb> values}) : _values = values;
  final int size;
  final List<_Rgb> _values;

  static Future<CubeLut> read(String path) async {
    final file = File(path);
    if (!await file.exists()) throw FileSystemException('LUT file not found.', path);
    if (await file.length() > 8 * 1024 * 1024) throw StateError('LUT file is too large. Maximum is 8 MB.');
    final lines = await file.readAsLines();
    var size = 0;
    final values = <_Rgb>[];
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final upper = line.toUpperCase();
      if (upper.startsWith('TITLE') || upper.startsWith('DOMAIN_MIN') || upper.startsWith('DOMAIN_MAX')) continue;
      if (upper.startsWith('LUT_3D_SIZE')) {
        final parts = line.split(RegExp(r'\s+'));
        size = int.parse(parts[1]);
        if (size < 2 || size > 65) throw const FormatException('Only 3D LUT sizes from 2 to 65 are supported.');
        continue;
      }
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 3) values.add(_Rgb(double.parse(parts[0]), double.parse(parts[1]), double.parse(parts[2])));
    }
    if (size == 0) throw const FormatException('Missing LUT_3D_SIZE in .cube file.');
    final expected = size * size * size;
    if (values.length != expected) throw FormatException('Expected $expected LUT samples, found ${values.length}.');
    return CubeLut._(size: size, values: values);
  }

  img.Image apply(img.Image source, double intensity) {
    final out = source.clone();
    final amount = intensity.clamp(0.0, 1.0).toDouble();
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        final p = source.getPixel(x, y);
        final mapped = _sample(p.r / 255.0, p.g / 255.0, p.b / 255.0);
        out.setPixelRgba(x, y, _byte(_mix(p.r.toDouble(), mapped.r * 255, amount)), _byte(_mix(p.g.toDouble(), mapped.g * 255, amount)), _byte(_mix(p.b.toDouble(), mapped.b * 255, amount)), p.a.toInt());
      }
    }
    return out;
  }

  _Rgb _sample(double r, double g, double b) {
    final maxIndex = size - 1;
    final rf = r.clamp(0.0, 1.0) * maxIndex;
    final gf = g.clamp(0.0, 1.0) * maxIndex;
    final bf = b.clamp(0.0, 1.0) * maxIndex;
    final r0 = rf.floor().clamp(0, maxIndex);
    final g0 = gf.floor().clamp(0, maxIndex);
    final b0 = bf.floor().clamp(0, maxIndex);
    final r1 = math.min(r0 + 1, maxIndex);
    final g1 = math.min(g0 + 1, maxIndex);
    final b1 = math.min(b0 + 1, maxIndex);
    final c000 = _at(r0, g0, b0);
    final c001 = _at(r0, g0, b1);
    final c010 = _at(r0, g1, b0);
    final c011 = _at(r0, g1, b1);
    final c100 = _at(r1, g0, b0);
    final c101 = _at(r1, g0, b1);
    final c110 = _at(r1, g1, b0);
    final c111 = _at(r1, g1, b1);
    final c00 = _Rgb.mix(c000, c100, rf - r0);
    final c01 = _Rgb.mix(c001, c101, rf - r0);
    final c10 = _Rgb.mix(c010, c110, rf - r0);
    final c11 = _Rgb.mix(c011, c111, rf - r0);
    return _Rgb.mix(_Rgb.mix(c00, c10, gf - g0), _Rgb.mix(c01, c11, gf - g0), bf - b0);
  }

  _Rgb _at(int r, int g, int b) => _values[(r * size * size) + (g * size) + b];
  static double _mix(double a, double b, double t) => a + (b - a) * t;
  static int _byte(double v) => v.round().clamp(0, 255).toInt();
}

class _Recipe {
  const _Recipe(this.red, this.green, this.blue, this.saturation, this.contrast);
  final double red;
  final double green;
  final double blue;
  final double saturation;
  final double contrast;
}

class _Rgb {
  const _Rgb(this.r, this.g, this.b);
  final double r;
  final double g;
  final double b;
  static _Rgb mix(_Rgb a, _Rgb b, double t) => _Rgb(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t);
}
