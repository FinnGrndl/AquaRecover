import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/timeline/timeline_project.dart';
import '../../../core/timeline/timeline_render_plan.dart';

/// Allocation-light key evaluation with the plan's semantics: linear
/// between neighbouring keys, clamped to the first and last key outside
/// them. Same results as [TimelineRenderPlan.evaluateLayer] and
/// [TimelineRenderPlan.evaluateClip], but a binary search instead of copying
/// every key on every frame.
abstract final class PreviewKeys {
  /// [keys] (sorted, at least one) at [u] seconds into the layer.
  static LayerKey layerAt(List<LayerKey> keys, double u) {
    final (a, b, f) = _bracket(keys.length, (i) => keys[i].t, u);
    final ka = keys[a], kb = keys[b];
    if (a == b) {
      return LayerKey(
        t: u,
        x: ka.x,
        y: ka.y,
        w: ka.w,
        h: ka.h,
        rotation: ka.rotation,
        opacity: ka.opacity,
      );
    }
    double lerp(double p, double q) => p + (q - p) * f;
    return LayerKey(
      t: u,
      x: lerp(ka.x, kb.x),
      y: lerp(ka.y, kb.y),
      w: lerp(ka.w, kb.w),
      h: lerp(ka.h, kb.h),
      rotation: lerp(ka.rotation, kb.rotation),
      opacity: lerp(ka.opacity, kb.opacity),
    );
  }

  /// [keys] at [u] seconds into the clip; identity when there are none.
  static TransformKey clipAt(List<TransformKey> keys, double u) {
    if (keys.isEmpty) return TransformKey(t: u);
    final (a, b, f) = _bracket(keys.length, (i) => keys[i].t, u);
    final ka = keys[a], kb = keys[b];
    if (a == b) {
      return TransformKey(
        t: u,
        scale: ka.scale,
        x: ka.x,
        y: ka.y,
        rotation: ka.rotation,
      );
    }
    double lerp(double p, double q) => p + (q - p) * f;
    return TransformKey(
      t: u,
      scale: lerp(ka.scale, kb.scale),
      x: lerp(ka.x, kb.x),
      y: lerp(ka.y, kb.y),
      rotation: lerp(ka.rotation, kb.rotation),
    );
  }

  /// Indices of the keys around [u] and the blend between them; both indices
  /// are equal when [u] is outside the keys.
  static (int, int, double) _bracket(
    int length,
    double Function(int index) timeOf,
    double u,
  ) {
    if (u <= timeOf(0)) return (0, 0, 0);
    final last = length - 1;
    if (u > timeOf(last)) return (last, last, 0);
    // The first key at or after u (index ≥ 1, because u > the first key).
    var lo = 1, hi = last;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (timeOf(mid) >= u) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    final t0 = timeOf(lo - 1), t1 = timeOf(lo);
    final span = t1 - t0;
    return (lo - 1, lo, span <= 0 ? 1.0 : (u - t0) / span);
  }
}

/// Plan pixels to view points. The viewer shows the canvas at the project's
/// aspect, so one uniform [scale] (view width / plan width) maps both axes.
abstract final class PreviewGeometry {
  /// View points per plan pixel.
  static double scaleFor(Size view, int planWidth) =>
      planWidth <= 0 ? 0 : view.width / planWidth;

  /// The main clip transform in view units: with `C` the view centre, a
  /// point `p` of the fitted frame goes to `C + (x, y)·scale + R(rotation) ·
  /// keyScale · (p − C)`: scale, rotate clockwise about the centre, then
  /// translate.
  static Matrix4 clipMatrix(TransformKey key, Size view, double scale) {
    final cx = view.width / 2, cy = view.height / 2;
    final radians = key.rotation * math.pi / 180;
    final cos = math.cos(radians) * key.scale;
    final sin = math.sin(radians) * key.scale;
    // x' = a·x + b·y + e, y' = c·x + d·y + f.
    final a = cos, b = -sin, c = sin, d = cos;
    final e = cx + key.x * scale - a * cx - b * cy;
    final f = cy + key.y * scale - c * cx - d * cy;
    return Matrix4(a, c, 0, 0, b, d, 0, 0, 0, 0, 1, 0, e, f, 0, 1);
  }

  /// Where [p] (view units, in the fitted frame) lands under [clipMatrix],
  /// written out directly for tests and hit testing.
  static Offset applyClipKey(
    TransformKey key,
    Size view,
    double scale,
    Offset p,
  ) {
    final c = view.center(Offset.zero);
    final radians = key.rotation * math.pi / 180;
    final v = (p - c) * key.scale;
    final rotated = Offset(
      v.dx * math.cos(radians) - v.dy * math.sin(radians),
      v.dx * math.sin(radians) + v.dy * math.cos(radians),
    );
    return c + Offset(key.x, key.y) * scale + rotated;
  }

  /// The unrotated rect of a layer key in view units.
  static Rect layerRect(LayerKey key, double scale) =>
      Rect.fromLTWH(key.x * scale, key.y * scale, key.w * scale, key.h * scale);

  /// Clockwise rotation of a layer key in radians, about its rect centre.
  static double layerRadians(LayerKey key) => key.rotation * math.pi / 180;

  /// A [media]-shaped frame fitted into [canvas] and centred: whole frame
  /// visible for [PlanFit.contain], canvas covered for [PlanFit.cover].
  static Rect fittedRect(Size media, Size canvas, PlanFit fit) {
    if (media.isEmpty || canvas.isEmpty) return Offset.zero & canvas;
    final sx = canvas.width / media.width, sy = canvas.height / media.height;
    final f = fit == PlanFit.contain ? math.min(sx, sy) : math.max(sx, sy);
    return Rect.fromCenter(
      center: canvas.center(Offset.zero),
      width: media.width * f,
      height: media.height * f,
    );
  }
}

/// Colour matrices in the `ColorFilter.matrix` form (4×5, offsets 0…255).
abstract final class PreviewColor {
  /// The grade matrix ([gradeBytes], already in byte units, e.g. from
  /// `GpuPreviewFilter.matrixFor`) followed by an effect [effect] matrix
  /// (offsets 0…1, as in [PlanFilters.colorMatrix]) as one matrix, so one
  /// `ColorFiltered` does both. `null` when there is neither.
  static List<double>? combine({
    List<double>? gradeBytes,
    List<double>? effect,
  }) {
    if (effect == null) return gradeBytes;
    final effectBytes = ColorMatrices.withByteOffsets(effect);
    return gradeBytes == null
        ? effectBytes
        : ColorMatrices.then(gradeBytes, effectBytes);
  }
}

/// Audio levels of plan segments during preview playback.
abstract final class PreviewAudioMath {
  /// Gain of [segment] at timeline time [t]: its volume times the fade-in
  /// and fade-out ramps; 0 outside the segment.
  static double gainAt(PlanAudio segment, double t) {
    if (t < segment.start || t >= segment.end) return 0;
    var gain = segment.volume;
    if (segment.fadeIn > 0) {
      gain *= ((t - segment.start) / segment.fadeIn).clamp(0.0, 1.0);
    }
    if (segment.fadeOut > 0) {
      gain *= ((segment.end - t) / segment.fadeOut).clamp(0.0, 1.0);
    }
    return gain.clamp(0.0, 1.0).toDouble();
  }

  /// Smallest volume change worth a platform call.
  static const volumeStep = 0.02;

  /// Least time between two volume calls of one player while it fades.
  static const volumeInterval = 0.08;

  /// Whether a player at volume [current], last set at [lastSetAt] seconds,
  /// should be set to [next] at [now]: never for tiny changes, at most every
  /// [volumeInterval] while fading, but always when reaching silence or a
  /// steady level after a big jump, so fades end exactly.
  static bool shouldSetVolume({
    required double? current,
    required double next,
    required double lastSetAt,
    required double now,
  }) {
    if (current == null) return true;
    final delta = (next - current).abs();
    if (delta < 1e-4) return false;
    if (next == 0) return true;
    if (delta < volumeStep) return false;
    return now - lastSetAt >= volumeInterval;
  }
}

/// Film grain placement: a new pattern every movie frame, from a cheap hash
/// of the frame number, so scrubbing and playback show the same grain.
abstract final class PreviewGrainMath {
  /// Offset into a [tileSize] noise tile for timeline time [t] at
  /// [frameRate] frames per second.
  static Offset offsetFor(double t, int frameRate, int tileSize) {
    final frame = (t * math.max(1, frameRate)).floor();
    var h = (frame * 0x9E3779B1) & 0xffffffff;
    h ^= h >> 15;
    h = (h * 0x85EBCA77) & 0xffffffff;
    h ^= h >> 13;
    return Offset(
      (h & 0xffff) % tileSize.toDouble(),
      ((h >> 16) & 0xffff) % tileSize.toDouble(),
    );
  }

  /// Opacity of a noise tile whose values have standard deviation
  /// [tileStd] that gives roughly [grain] standard deviation in mid-tones
  /// when drawn with an overlay blend.
  static double opacityFor(double grain, double tileStd) =>
      tileStd <= 0 ? 0 : (grain / tileStd).clamp(0.0, 1.0).toDouble();
}
