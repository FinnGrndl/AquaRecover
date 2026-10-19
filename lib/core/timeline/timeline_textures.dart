import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'timeline_render_plan.dart';
import 'timeline_project.dart';

/// Size of [spec] rasterised for a [canvasWidth] × [canvasHeight] movie at 1:1
/// (font size `fontScale × canvasHeight`), padding included, in whole output
/// pixels. Set an overlay's `mediaAspect` from it.
ui.Size measureTitle(
  TitleSpec spec, {
  required int canvasWidth,
  required int canvasHeight,
}) => _TitleLayout(spec, canvasWidth, canvasHeight).size;

/// Width / height of [spec] rasterised for the canvas; a
/// [TitleAspectResolver] for [TimelineCompiler.compile].
double titleAspectRatio(TitleSpec spec, int canvasWidth, int canvasHeight) {
  final size = measureTitle(
    spec,
    canvasWidth: canvasWidth,
    canvasHeight: canvasHeight,
  );
  return size.width / size.height;
}

/// [spec] as a PNG cropped to the text box plus padding. Without [width] it
/// is [measureTitle] pixels; with it, scaled so the PNG is [width] pixels
/// wide, so a title is rasterised at exactly the size it is shown. No drop
/// shadows: contrast comes from an outline or a box.
Future<Uint8List> rasterizeTitle(
  TitleSpec spec, {
  required int canvasWidth,
  required int canvasHeight,
  int? width,
}) async {
  final layout = _TitleLayout(spec, canvasWidth, canvasHeight);
  final size = layout.size;
  final scale = width == null ? 1.0 : width / size.width;
  final outW = math.max(1, width ?? size.width.round());
  final outH = math.max(1, (size.height * scale).round());
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(scale);
  layout.paint(canvas);
  return _encode(recorder.endRecording(), outW, outH);
}

/// The texture of a [EffectType.usesTexture] effect at [intensity], [width] ×
/// [height] pixels, as a PNG:
/// - vignette: black, alpha `i·smoothstep(0.35, 1.05, d)` with `d` the
///   distance from the centre over the half-diagonal;
/// - cinemaBars: opaque black bars top and bottom
///   ([TimelineCompiler.cinemaBarHeight]);
/// - sunRays: nine soft white rays fanning down from above the top edge,
///   alpha up to `0.55·i`;
/// - caustics: a seamless white caustic network, alpha up to `0.45·i`,
///   strongest at the top.
Future<Uint8List> rasterizeEffectTexture(
  EffectType type,
  double intensity,
  int width,
  int height,
) async {
  if (width <= 0 || height <= 0) {
    throw ArgumentError('Texture size must be positive, not $width×$height.');
  }
  final i = intensity.clamp(0.0, 1.0).toDouble();
  final w = width.toDouble(), h = height.toDouble();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final full = ui.Rect.fromLTWH(0, 0, w, h);
  switch (type) {
    case EffectType.vignette:
      const steps = 32;
      canvas.drawRect(
        full,
        ui.Paint()
          ..shader = ui.Gradient.radial(
            ui.Offset(w / 2, h / 2),
            math.sqrt(w * w + h * h) / 2,
            [
              for (var k = 0; k <= steps; k++)
                _black(i * _smoothstep(0.35, 1.05, k / steps)),
            ],
            [for (var k = 0; k <= steps; k++) k / steps],
          ),
      );
    case EffectType.cinemaBars:
      final bar = TimelineCompiler.cinemaBarHeight(i, width, height).round();
      if (bar > 0) {
        final paint = ui.Paint()..color = const ui.Color(0xFF000000);
        canvas
          ..drawRect(ui.Rect.fromLTWH(0, 0, w, bar.toDouble()), paint)
          ..drawRect(ui.Rect.fromLTWH(0, h - bar, w, bar.toDouble()), paint);
      }
    case EffectType.sunRays:
      final rays = await _pixelsToImage(
        _sunRays(i, width, height),
        width,
        height,
      );
      canvas.drawImage(rays, ui.Offset.zero, ui.Paint());
      rays.dispose();
    case EffectType.caustics:
      const tileSize = 384;
      final tile = await _pixelsToImage(
        _causticTile(tileSize),
        tileSize,
        tileSize,
      );
      final period = 0.5 * math.min(w, h);
      final s = period / tileSize;
      canvas.drawRect(
        full,
        ui.Paint()
          ..filterQuality = ui.FilterQuality.medium
          ..shader = ui.ImageShader(
            tile,
            ui.TileMode.repeated,
            ui.TileMode.repeated,
            Float64List.fromList([
              s, 0, 0, 0, //
              0, s, 0, 0, //
              0, 0, 1, 0, //
              0, 0, 0, 1, //
            ]),
          ),
      );
      const steps = 16;
      canvas.drawRect(
        full,
        ui.Paint()
          ..blendMode = ui.BlendMode.dstIn
          ..shader = ui.Gradient.linear(
            ui.Offset.zero,
            ui.Offset(0, h),
            [
              for (var k = 0; k <= steps; k++)
                _black(0.45 * i * (1 - 0.7 * _smoothstep(0, 1, k / steps))),
            ],
            [for (var k = 0; k <= steps; k++) k / steps],
          ),
      );
      tile.dispose();
    default:
      throw ArgumentError.value(type, 'type', 'has no texture');
  }
  return _encode(recorder.endRecording(), width, height);
}

/// Rasterises any [GeneratedSpec] to a PNG.
Future<Uint8List> rasterizeGenerated(GeneratedSpec spec) => switch (spec) {
  TitleTexture() => rasterizeTitle(
    spec.title,
    canvasWidth: spec.canvasWidth,
    canvasHeight: spec.canvasHeight,
    width: spec.width,
  ),
  EffectTexture() => rasterizeEffectTexture(
    spec.effect,
    spec.intensity,
    spec.width,
    spec.height,
  ),
};

/// Writes generated titles and textures as PNG files named by a hash of
/// their spec, so each is rasterised once per spec and size, even across
/// launches and renders.
class GeneratedTextureCache {
  GeneratedTextureCache({
    Future<Directory> Function()? directory,
    Future<Uint8List> Function(GeneratedSpec spec)? rasterize,
  }) : _directory = directory ?? _defaultDirectory,
       _rasterize = rasterize ?? rasterizeGenerated;

  /// Bump when a rasteriser changes its pixels, so stale files are not
  /// reused.
  static const version = 1;

  final Future<Directory> Function() _directory;
  final Future<Uint8List> Function(GeneratedSpec spec) _rasterize;
  final Map<String, Future<String>> _paths = {};

  static Future<Directory> _defaultDirectory() async {
    final base = await getTemporaryDirectory();
    return Directory(p.join(base.path, 'AquaRecover textures'));
  }

  /// File name of [spec]: its kind plus a 64-bit FNV-1a hash of its key.
  static String fileNameFor(GeneratedSpec spec) {
    final kind = switch (spec) {
      TitleTexture() => 'title',
      EffectTexture(:final effect) => effect.id,
    };
    return '${kind}_${_fnv1a64(utf8.encode('v$version:${spec.cacheKey}'))}.png';
  }

  /// The PNG of [spec], rasterised and written on first use.
  Future<String> pathFor(GeneratedSpec spec) {
    final name = fileNameFor(spec);
    return _paths[name] ??= _write(spec, name).catchError((Object error) {
      _paths.remove(name);
      throw error;
    });
  }

  Future<String> _write(GeneratedSpec spec, String name) async {
    final dir = await _directory();
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, name));
    if (await file.exists() && await file.length() > 0) return file.path;
    final temp = File('${file.path}.${DateTime.now().microsecondsSinceEpoch}');
    await temp.writeAsBytes(await _rasterize(spec), flush: true);
    await temp.rename(file.path);
    return file.path;
  }

  static String _fnv1a64(List<int> bytes) {
    // Two 32-bit halves keep the arithmetic exact on every platform.
    var hi = 0xcbf29ce4, lo = 0x84222325;
    for (final byte in bytes) {
      lo ^= byte;
      // Multiply the 64-bit (hi, lo) by the FNV prime 0x100000001b3.
      final loMul = lo * 0x1b3;
      final carry = loMul ~/ 0x100000000;
      final newLo = loMul & 0xffffffff;
      final newHi = (hi * 0x1b3 + (lo << 8) + carry) & 0xffffffff;
      hi = newHi;
      lo = newLo;
    }
    return hi.toRadixString(16).padLeft(8, '0') +
        lo.toRadixString(16).padLeft(8, '0');
  }
}

/// Paragraphs and placement of one title, shared by measuring and painting so
/// the rasterised aspect always matches [measureTitle].
class _TitleLayout {
  factory _TitleLayout(TitleSpec spec, int canvasWidth, int canvasHeight) {
    final fontPx = spec.fontScale * canvasHeight;
    final color = ui.Color(spec.color);
    final weight = spec.bold ? ui.FontWeight.w700 : ui.FontWeight.w400;
    final align = switch (spec.align) {
      TitleAlign.left => ui.TextAlign.left,
      TitleAlign.center => ui.TextAlign.center,
      TitleAlign.right => ui.TextAlign.right,
    };
    final maxWidth = canvasWidth * 0.9;
    final lines = <_TitleLine>[];
    double padX, padY;
    double? stroke;
    var box = false;
    var radius = 0.0;
    var gap = 0.0;
    switch (spec.style) {
      case TitleStyle.classic:
        padX = padY = 0.12 * fontPx;
        lines.add(_TitleLine(spec.text, fontPx, color, weight));
      case TitleStyle.outline:
        stroke = (fontPx / 30).clamp(2.0, 3.0).toDouble();
        padX = padY = stroke + 0.12 * fontPx;
        lines.add(_TitleLine(spec.text, fontPx, color, weight));
      case TitleStyle.boldBox:
        box = true;
        padX = 0.45 * fontPx;
        padY = 0.22 * fontPx;
        radius = 0.22 * fontPx;
        lines.add(_TitleLine(spec.text, fontPx, color, weight));
      case TitleStyle.caption:
        final px = fontPx * 0.6;
        box = true;
        padX = 0.5 * px;
        padY = 0.25 * px;
        radius = 0.18 * px;
        lines.add(_TitleLine(spec.text, px, color, ui.FontWeight.w500));
      case TitleStyle.diveStamp:
        padX = padY = 0.12 * fontPx;
        gap = 0.12 * fontPx;
        final split = spec.text.indexOf('\n');
        final head = split < 0 ? spec.text : spec.text.substring(0, split);
        lines.add(
          _TitleLine(
            head.toUpperCase(),
            fontPx,
            color,
            weight,
            letterSpacing: 0.12 * fontPx,
          ),
        );
        if (split >= 0) {
          final small = fontPx * 0.5;
          lines.add(
            _TitleLine(
              spec.text.substring(split + 1).toUpperCase(),
              small,
              color.withValues(alpha: color.a * 0.85),
              ui.FontWeight.w500,
              letterSpacing: 0.2 * small,
            ),
          );
        }
    }
    final textWidth = math.max(1.0, maxWidth - 2 * padX);
    final paragraphs = [
      for (final line in lines) line.build(align, textWidth, stroke: stroke),
    ];
    final contentW = paragraphs.fold(0.0, (m, l) => math.max(m, l.width));
    final contentH =
        paragraphs.fold(0.0, (sum, l) => sum + l.height) +
        gap * math.max(0, paragraphs.length - 1);
    final size = ui.Size(
      (contentW + 2 * padX).ceilToDouble(),
      (contentH + 2 * padY).ceilToDouble(),
    );
    final offsets = <ui.Offset>[];
    var y = (size.height - contentH) / 2;
    for (final paragraph in paragraphs) {
      final x = switch (spec.align) {
        TitleAlign.left => padX,
        TitleAlign.center => (size.width - paragraph.width) / 2,
        TitleAlign.right => size.width - padX - paragraph.width,
      };
      offsets.add(ui.Offset(x, y));
      y += paragraph.height + gap;
    }
    return _TitleLayout._(
      size: size,
      paragraphs: paragraphs,
      offsets: offsets,
      background: box ? ui.Color(spec.backgroundColor) : null,
      radius: radius,
    );
  }

  _TitleLayout._({
    required this.size,
    required this.paragraphs,
    required this.offsets,
    required this.background,
    required this.radius,
  });

  final ui.Size size;
  final List<_LaidOutLine> paragraphs;
  final List<ui.Offset> offsets;
  final ui.Color? background;
  final double radius;

  void paint(ui.Canvas canvas) {
    if (background case final color?) {
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          ui.Offset.zero & size,
          ui.Radius.circular(radius),
        ),
        ui.Paint()..color = color,
      );
    }
    for (var k = 0; k < paragraphs.length; k++) {
      final line = paragraphs[k];
      if (line.stroke case final stroke?) {
        canvas.drawParagraph(stroke, offsets[k]);
      }
      canvas.drawParagraph(line.fill, offsets[k]);
    }
  }
}

class _TitleLine {
  _TitleLine(
    this.text,
    this.fontSize,
    this.color,
    this.weight, {
    this.letterSpacing = 0,
  });

  final String text;
  final double fontSize;
  final ui.Color color;
  final ui.FontWeight weight;
  final double letterSpacing;

  _LaidOutLine build(ui.TextAlign align, double maxWidth, {double? stroke}) {
    ui.Paragraph layout(double width, {ui.Paint? foreground}) {
      final builder =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(
                textAlign: align,
                fontSize: fontSize,
                fontWeight: weight,
              ),
            )
            ..pushStyle(
              ui.TextStyle(
                color: foreground == null ? color : null,
                foreground: foreground,
                fontSize: fontSize,
                fontWeight: weight,
                letterSpacing: letterSpacing,
              ),
            )
            ..addText(text);
      return builder.build()..layout(ui.ParagraphConstraints(width: width));
    }

    final probe = layout(maxWidth);
    // Re-lay out at the text's own width so alignment works inside the box.
    final width = math.min(maxWidth, probe.longestLine.ceilToDouble() + 1);
    final fill = layout(width);
    final outline = stroke == null
        ? null
        : layout(
            width,
            foreground: ui.Paint()
              ..style = ui.PaintingStyle.stroke
              ..strokeWidth = stroke
              ..strokeJoin = ui.StrokeJoin.round
              ..color = const ui.Color(0xE6061826),
          );
    probe.dispose();
    return _LaidOutLine(fill, outline, width, fill.height);
  }
}

class _LaidOutLine {
  const _LaidOutLine(this.fill, this.stroke, this.width, this.height);

  final ui.Paragraph fill;
  final ui.Paragraph? stroke;
  final double width;
  final double height;
}

Future<Uint8List> _encode(ui.Picture picture, int width, int height) async {
  final image = await picture.toImage(width, height);
  picture.dispose();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Could not encode a texture.');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

Future<ui.Image> _pixelsToImage(Uint8List rgba, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

ui.Color _black(double alpha) =>
    ui.Color.fromARGB((alpha.clamp(0.0, 1.0) * 255).round(), 0, 0, 0);

double _smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Premultiplied white RGBA pixels with the given alpha in 0…1.
void _putWhite(Uint8List rgba, int index, double alpha) {
  final a = (alpha.clamp(0.0, 1.0) * 255).round();
  rgba[index] = a;
  rgba[index + 1] = a;
  rgba[index + 2] = a;
  rgba[index + 3] = a;
}

/// Ray angle from vertical in degrees, half-width in degrees, strength, and
/// length in texture heights from the source.
const _rays = <(double, double, double, double)>[
  (-31, 2.2, 0.55, 1.25),
  (-23, 3.0, 0.8, 1.45),
  (-16, 1.8, 0.6, 1.3),
  (-9, 3.4, 1.0, 1.55),
  (-2, 2.0, 0.7, 1.35),
  (5, 2.8, 0.9, 1.5),
  (12, 1.9, 0.65, 1.3),
  (19, 2.6, 0.75, 1.4),
  (27, 2.1, 0.55, 1.25),
];

/// Soft beams fanning down from a source half a texture height above the top
/// edge, so they look nearly parallel, brightest near the top of the canvas.
Uint8List _sunRays(double intensity, int width, int height) {
  final rgba = Uint8List(width * height * 4);
  final ox = width * 0.42, oy = -height * 0.5;
  const toRad = math.pi / 180;
  final peak = 0.55 * intensity;
  for (var y = 0; y < height; y++) {
    final dy = y + 0.5 - oy;
    for (var x = 0; x < width; x++) {
      final dx = x + 0.5 - ox;
      final angle = math.atan2(dx, dy);
      final r = math.sqrt(dx * dx + dy * dy) / height;
      final near = _smoothstep(0.45, 0.7, r);
      var best = 0.0;
      for (final (deg, halfWidth, strength, length) in _rays) {
        final off = (angle - deg * toRad) / (halfWidth * toRad);
        if (off.abs() > 3) continue;
        final along = 1 - _smoothstep(0.6, length, r);
        final value = strength * math.exp(-0.5 * off * off) * along;
        if (value > best) best = value;
      }
      _putWhite(rgba, (y * width + x) * 4, peak * near * best);
    }
  }
  return rgba;
}

/// A seamless caustic tile: the edges of two domain-warped periodic Voronoi
/// fields, brightest where cells meet.
Uint8List _causticTile(int size) {
  final rgba = Uint8List(size * size * 4);
  final a = _VoronoiField(5, 11), b = _VoronoiField(4, 29);
  const tau = 2 * math.pi;
  for (var y = 0; y < size; y++) {
    final v = (y + 0.5) / size;
    for (var x = 0; x < size; x++) {
      final u = (x + 0.5) / size;
      final wu = u + 0.035 * math.sin(tau * (2 * v + 0.17));
      final wv = v + 0.035 * math.sin(tau * (2 * u + 0.61));
      final lineA = 1 - _smoothstep(0, 0.22, a.edge(wu, wv));
      final lineB =
          1 -
          _smoothstep(
            0,
            0.2,
            b.edge(
              u + 0.05 * math.sin(tau * (u + v + 0.3)),
              v + 0.05 * math.sin(tau * (u - v + 0.8)),
            ),
          );
      final c = math.max(lineA, 0.8 * lineB);
      final shimmer = 0.8 + 0.2 * math.sin(tau * (u + 2 * v));
      _putWhite(rgba, (y * size + x) * 4, math.pow(c, 1.6) * shimmer);
    }
  }
  return rgba;
}

/// Worley noise on a torus: one jittered point per cell of a [cells] × [cells]
/// grid over the unit square, wrapping at the edges.
class _VoronoiField {
  _VoronoiField(this.cells, int seed)
    : _points = List.generate(cells * cells, (index) {
        final random = math.Random(seed * 7919 + index);
        return (
          0.15 + 0.7 * random.nextDouble(),
          0.15 + 0.7 * random.nextDouble(),
        );
      });

  final int cells;
  final List<(double, double)> _points;

  /// F2 − F1 in cell units at (u, v): near 0 on the cell borders.
  double edge(double u, double v) {
    final px = u * cells, py = v * cells;
    final ix = px.floor(), iy = py.floor();
    var f1 = double.infinity, f2 = double.infinity;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final cx = ix + dx, cy = iy + dy;
        final (jx, jy) = _points[(cy % cells) * cells + (cx % cells)];
        final ex = cx + jx - px, ey = cy + jy - py;
        final d = math.sqrt(ex * ex + ey * ey);
        if (d < f1) {
          f2 = f1;
          f1 = d;
        } else if (d < f2) {
          f2 = d;
        }
      }
    }
    return f2 - f1;
  }
}
