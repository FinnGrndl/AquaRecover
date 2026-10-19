import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../../core/timeline/timeline_project.dart';
import '../../../core/timeline/timeline_render_plan.dart';
import '../../../core/timeline/timeline_textures.dart';

/// Turns a generated spec into a decoded image.
typedef PreviewRasterizer = Future<ui.Image> Function(GeneratedSpec spec);

/// The export's rasteriser ([rasterizeGenerated]) decoded to an image, so the
/// preview draws exactly the pixels the movie gets, at view size.
Future<ui.Image> rasterizePreviewTexture(GeneratedSpec spec) async {
  final png = await rasterizeGenerated(spec);
  final codec = await ui.instantiateImageCodec(png);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

/// Sizes generated textures for the view instead of the output.
abstract final class PreviewTextureSizing {
  /// Long-side cap of effect textures in device pixels.
  static const maxEffectSide = 1024;

  /// Sun rays are very soft and rasterised pixel by pixel in Dart, so they
  /// are drawn from a smaller texture.
  static const maxSoftSide = 512;

  /// [spec] of [layer] re-sized for [pixelRatio] device pixels per plan
  /// pixel: a title as wide as its largest on-screen width, an effect
  /// texture as large as its on-screen rect (capped).
  static GeneratedSpec specFor(
    PlanLayer layer,
    GeneratedSpec spec,
    double pixelRatio,
  ) {
    switch (spec) {
      case TitleTexture():
        return TitleTexture(
          spec.title,
          width: (spec.width * pixelRatio).round().clamp(
            1,
            TimelineCompiler.maxTitleTextureWidth,
          ),
          canvasWidth: spec.canvasWidth,
          canvasHeight: spec.canvasHeight,
        );
      case EffectTexture():
        final key = layer.keys.first;
        var w = key.w * pixelRatio, h = key.h * pixelRatio;
        final cap = spec.effect == EffectType.sunRays
            ? maxSoftSide
            : maxEffectSide;
        final fit = math.min(1.0, cap / math.max(w, h));
        w *= fit;
        h *= fit;
        return EffectTexture(
          spec.effect,
          spec.intensity,
          math.max(1, w.round()),
          math.max(1, h.round()),
        );
    }
  }
}

/// The view-sized spec and cache key of each generated layer, computed once
/// per plan layer and pixel ratio (the key is a JSON string, too costly to
/// rebuild every frame).
class PreviewTextureSpecs {
  final Expando<_ScaledSpec> _memo = Expando('preview texture specs');

  ({GeneratedSpec spec, String key}) of(
    PlanLayer layer,
    GeneratedSpec spec,
    double pixelRatio,
  ) {
    final cached = _memo[layer];
    if (cached != null && cached.pixelRatio == pixelRatio) return cached.value;
    final scaled = PreviewTextureSizing.specFor(layer, spec, pixelRatio);
    final value = (spec: scaled, key: scaled.cacheKey);
    _memo[layer] = _ScaledSpec(pixelRatio, value);
    return value;
  }
}

class _ScaledSpec {
  const _ScaledSpec(this.pixelRatio, this.value);

  final double pixelRatio;
  final ({GeneratedSpec spec, String key}) value;
}

/// Decoded titles and effect textures by spec key, least recently used
/// evicted beyond [maxBytes]. Callers get their own handle
/// ([ui.Image.clone]) and dispose it, so evicting never pulls an image out
/// from under a widget that still draws it.
class PreviewTextureCache {
  PreviewTextureCache({PreviewRasterizer? rasterize, this.maxBytes = 48 << 20})
    : _rasterize = rasterize ?? rasterizePreviewTexture;

  final PreviewRasterizer _rasterize;
  final int maxBytes;
  final LinkedHashMap<String, ui.Image> _images = LinkedHashMap();
  final Map<String, Future<bool>> _loading = {};
  int _bytes = 0;
  bool _disposed = false;

  /// Bytes of decoded pixels held.
  int get bytes => _bytes;

  /// Keys of the images held, least recently used first.
  Iterable<String> get keys => _images.keys;

  /// A new handle to the image of [key] when it is ready, else `null`.
  ui.Image? acquire(String key) {
    final image = _images.remove(key);
    if (image == null) return null;
    _images[key] = image;
    return image.clone();
  }

  /// A new handle to the image of [spec] (cache key [key]), rasterising it
  /// once however many layers ask; `null` when it cannot be drawn.
  Future<ui.Image?> load(String key, GeneratedSpec spec) async {
    final ready = acquire(key);
    if (ready != null) return ready;
    if (_disposed) return null;
    final ok = await (_loading[key] ??= _fill(key, spec));
    return ok ? acquire(key) : null;
  }

  Future<bool> _fill(String key, GeneratedSpec spec) async {
    try {
      final image = await _rasterize(spec);
      if (_disposed) {
        image.dispose();
        return false;
      }
      _images.remove(key)?.dispose();
      _images[key] = image;
      _bytes += _sizeOf(image);
      _trim(keep: key);
      return true;
    } on Object {
      return false;
    } finally {
      _loading.remove(key);
    }
  }

  void _trim({required String keep}) {
    while (_bytes > maxBytes && _images.length > 1) {
      final oldest = _images.keys.firstWhere((k) => k != keep);
      final image = _images.remove(oldest)!;
      _bytes -= _sizeOf(image);
      image.dispose();
    }
  }

  static int _sizeOf(ui.Image image) => image.width * image.height * 4;

  /// Drops every image; handles already given out stay valid until their
  /// owners dispose them.
  void dispose() {
    _disposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _bytes = 0;
  }
}

/// Draws one generated texture stretched over its parent, with opacity
/// applied by the image paint (no save layer). Keeps showing the previous
/// image while a changed one (new text, new size) rasterises.
class PreviewTextureView extends StatefulWidget {
  const PreviewTextureView({
    super.key,
    required this.cache,
    required this.textureKey,
    required this.spec,
    required this.opacity,
  });

  final PreviewTextureCache cache;
  final String textureKey;
  final GeneratedSpec spec;
  final double opacity;

  /// How long a changed texture waits before rasterising while an older one
  /// is still on screen, so typing or resizing does not queue a raster per
  /// frame.
  static const settle = Duration(milliseconds: 80);

  @override
  State<PreviewTextureView> createState() => _PreviewTextureViewState();
}

class _PreviewTextureViewState extends State<PreviewTextureView> {
  ui.Image? _image;
  String? _wanted;
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    _want();
  }

  @override
  void didUpdateWidget(PreviewTextureView old) {
    super.didUpdateWidget(old);
    if (widget.textureKey != _wanted || !identical(widget.cache, old.cache)) {
      _want();
    }
  }

  void _want() {
    final key = _wanted = widget.textureKey;
    _settle?.cancel();
    final cached = widget.cache.acquire(key);
    if (cached != null) {
      _show(cached);
    } else if (_image == null) {
      unawaited(_load());
    } else {
      _settle = Timer(PreviewTextureView.settle, () => unawaited(_load()));
    }
  }

  Future<void> _load() async {
    final key = widget.textureKey;
    final image = await widget.cache.load(key, widget.spec);
    if (!mounted || key != _wanted) {
      image?.dispose();
      return;
    }
    if (image != null) setState(() => _show(image));
  }

  void _show(ui.Image image) {
    _image?.dispose();
    _image = image;
  }

  @override
  void dispose() {
    _settle?.cancel();
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opacity = widget.opacity.clamp(0.0, 1.0).toDouble();
    return RawImage(
      image: opacity > 0 ? _image : null,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
      opacity: opacity < 1 ? AlwaysStoppedAnimation(opacity) : null,
    );
  }
}
