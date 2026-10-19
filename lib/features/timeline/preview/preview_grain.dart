import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'preview_math.dart';

/// A small tile of monochrome Gaussian noise around mid-grey, made once per
/// app run and drawn repeated with an overlay blend: mid-grey leaves a pixel
/// as it is, so the grain is zero-mean like the export's.
abstract final class PreviewGrainTile {
  static const size = 256;

  /// Standard deviation of the tile's values in 0…1 units.
  static const std = 0.18;

  static ui.Image? _image;
  static Future<ui.Image>? _loading;
  static final _listeners = <VoidCallback>{};

  /// The tile, or `null` while it is being made; [onReady] runs once it is.
  static ui.Image? image({VoidCallback? onReady}) {
    final image = _image;
    if (image != null) return image;
    if (onReady != null) _listeners.add(onReady);
    _loading ??= _make().then((image) {
      _image = image;
      final listeners = [..._listeners];
      _listeners.clear();
      for (final listener in listeners) {
        listener();
      }
      return image;
    });
    return null;
  }

  /// Stops [onReady] from being called.
  static void cancel(VoidCallback onReady) => _listeners.remove(onReady);

  static Future<ui.Image> _make() {
    final random = math.Random(0x5eed);
    final pixels = Uint8List(size * size * 4);
    for (var i = 0; i < size * size; i++) {
      // Box–Muller.
      final u1 = math.max(1e-9, random.nextDouble());
      final u2 = random.nextDouble();
      final z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
      final v = ((0.5 + std * z).clamp(0.0, 1.0) * 255).round();
      pixels
        ..[i * 4] = v
        ..[i * 4 + 1] = v
        ..[i * 4 + 2] = v
        ..[i * 4 + 3] = 255;
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      size,
      size,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}

/// Paints film grain of standard deviation [grain] (0…1 units) over its
/// box, shifted to [offset] in the noise tile (a new offset per movie frame
/// re-rolls the pattern without making new noise). One texel per device
/// pixel.
class PreviewGrainPainter extends CustomPainter {
  PreviewGrainPainter({
    required this.tile,
    required this.grain,
    required this.offset,
    required this.devicePixelRatio,
  });

  final ui.Image tile;
  final double grain;
  final Offset offset;
  final double devicePixelRatio;

  static final Paint _paint = Paint()
    ..blendMode = BlendMode.overlay
    ..filterQuality = FilterQuality.none;
  static ui.ImageShader? _shader;
  static ui.Image? _shaderTile;
  static double _shaderRatio = 0;

  @override
  void paint(Canvas canvas, Size size) {
    final opacity = PreviewGrainMath.opacityFor(grain, PreviewGrainTile.std);
    if (opacity <= 0 || size.isEmpty) return;
    final ratio = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
    if (!identical(_shaderTile, tile) || _shaderRatio != ratio) {
      _shader?.dispose();
      final s = 1 / ratio;
      _shader = ui.ImageShader(
        tile,
        TileMode.repeated,
        TileMode.repeated,
        Float64List.fromList([
          s, 0, 0, 0, //
          0, s, 0, 0, //
          0, 0, 1, 0, //
          0, 0, 0, 1, //
        ]),
        filterQuality: FilterQuality.none,
      );
      _shaderTile = tile;
      _shaderRatio = ratio;
    }
    final rect = Offset.zero & size;
    final shift = offset / ratio;
    _paint
      ..shader = _shader
      ..color = Color.fromRGBO(0, 0, 0, opacity);
    canvas
      ..save()
      ..clipRect(rect)
      ..translate(-shift.dx, -shift.dy)
      ..drawRect(rect.shift(shift), _paint)
      ..restore();
  }

  @override
  bool shouldRepaint(PreviewGrainPainter old) =>
      old.offset != offset ||
      old.grain != grain ||
      !identical(old.tile, tile) ||
      old.devicePixelRatio != devicePixelRatio;
}
