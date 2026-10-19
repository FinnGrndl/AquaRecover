import 'dart:convert';
import 'dart:math' as math;

import '../models/lut_profile.dart';
import '../models/restoration_settings.dart';
import 'timeline_project.dart';

/// How a main clip's frame is fitted into the canvas before its keys apply.
enum PlanFit {
  /// Whole frame visible, letterboxed in black.
  contain,

  /// Canvas filled, frame cropped; used when the clip moves.
  cover,
}

/// What a [PlanLayer] draws. Generated titles and textures are `image`.
enum PlanLayerKind { video, image, color }

/// Where a [PlanAudio] segment comes from.
enum PlanAudioOrigin { mainClip, overlay, track }

/// The pixels of a [PlanLayer].
sealed class PlanSource {
  const PlanSource();
}

/// A video or image file.
final class FileSource extends PlanSource {
  const FileSource(this.path);

  final String path;

  @override
  bool operator ==(Object other) => other is FileSource && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// A solid colour filling the layer rect.
final class ColorSource extends PlanSource {
  const ColorSource(this.argb);

  /// Unsigned 32-bit ARGB.
  final int argb;

  @override
  bool operator ==(Object other) => other is ColorSource && other.argb == argb;

  @override
  int get hashCode => argb.hashCode;
}

/// An image Dart generates (a title or an effect texture). The render service
/// writes it to a PNG before calling a native renderer, which then sees an
/// ordinary image layer.
final class GeneratedSource extends PlanSource {
  const GeneratedSource(this.spec);

  final GeneratedSpec spec;

  @override
  bool operator ==(Object other) =>
      other is GeneratedSource && other.spec == spec;

  @override
  int get hashCode => spec.hashCode;
}

/// Everything needed to rasterise a generated image, with value equality so
/// identical textures are generated once.
sealed class GeneratedSpec {
  const GeneratedSpec();

  /// A stable description; [cacheKey] hashes it.
  Map<String, Object?> toJson();

  /// Changes whenever the generated pixels would change.
  String get cacheKey => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      other is GeneratedSpec &&
      other.runtimeType == runtimeType &&
      other.cacheKey == cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;
}

/// A title rasterised [width] pixels wide (its height follows from the text)
/// for a [canvasWidth] × [canvasHeight] movie.
final class TitleTexture extends GeneratedSpec {
  const TitleTexture(
    this.title, {
    required this.width,
    required this.canvasWidth,
    required this.canvasHeight,
  });

  final TitleSpec title;
  final int width;
  final int canvasWidth;
  final int canvasHeight;

  @override
  Map<String, Object?> toJson() => {
    'type': 'title',
    'title': title.toJson(),
    'width': width,
    'canvasWidth': canvasWidth,
    'canvasHeight': canvasHeight,
  };
}

/// A [width] × [height] texture of a [EffectType.usesTexture] effect with the
/// intensity baked into its alpha.
final class EffectTexture extends GeneratedSpec {
  const EffectTexture(this.effect, this.intensity, this.width, this.height);

  final EffectType effect;
  final double intensity;
  final int width;
  final int height;

  @override
  Map<String, Object?> toJson() => {
    'type': 'effect',
    'effect': effect.id,
    'intensity': intensity,
    'width': width,
    'height': height,
  };
}

/// Per-pixel filters of a clip or layer, in output-pixel units.
class PlanFilters {
  const PlanFilters({
    this.colorMatrix,
    this.blurSigma = 0,
    this.sharpen = 0,
    this.sharpenSigma = 0,
    this.grain = 0,
  });

  static const none = PlanFilters();

  /// 4×5 row-major matrix with offsets in 0…1 (see [ColorMatrices]), applied
  /// after the grade and look; `null` when the item has no colour effect.
  final List<double>? colorMatrix;

  /// Gaussian blur sigma in output pixels, applied after fitting into the
  /// canvas (main clips) or the layer rect (layers).
  final double blurSigma;

  /// Unsharp-mask amount: `out = in + sharpen·(in − blur(in, sharpenSigma))`.
  final double sharpen;

  /// Blur sigma of the unsharp mask in output pixels.
  final double sharpenSigma;

  /// Standard deviation of zero-mean monochrome noise added per frame (in
  /// 0…1 units), a new pattern every frame.
  final double grain;

  bool get isEmpty =>
      colorMatrix == null && blurSigma <= 0 && sharpen <= 0 && grain <= 0;

  Map<String, Object?> toJson() => {
    'colorMatrix': colorMatrix == null ? null : [...colorMatrix!],
    'blurSigma': blurSigma,
    'sharpen': sharpen,
    'sharpenSigma': sharpenSigma,
    'grain': grain,
  };
}

/// Transform of a main clip at local time [t]. The clip is first fitted into
/// the canvas and centred; then, about the canvas centre, it is scaled by
/// [scale] and rotated by [rotation] degrees (clockwise on screen), and
/// finally moved by ([x], [y]) output pixels, y pointing down.
class TransformKey {
  const TransformKey({
    required this.t,
    this.scale = 1,
    this.x = 0,
    this.y = 0,
    this.rotation = 0,
  });

  final double t;
  final double scale, x, y, rotation;

  bool get isIdentity =>
      (scale - 1).abs() < _epsilon &&
      x.abs() < _epsilon &&
      y.abs() < _epsilon &&
      rotation.abs() < _epsilon;

  List<double> get _values => [t, scale, x, y, rotation];

  static TransformKey _fromValues(List<double> v) =>
      TransformKey(t: v[0], scale: v[1], x: v[2], y: v[3], rotation: v[4]);

  Map<String, Object?> toJson() => {
    't': t,
    'scale': scale,
    'x': x,
    'y': y,
    'rotation': rotation,
  };

  @override
  String toString() =>
      'TransformKey(t: $t, scale: $scale, x: $x, y: $y, rotation: $rotation)';
}

/// Placement of a layer at local time [t]: the unrotated rect ([x], [y], [w],
/// [h]) in output pixels with a top-left origin, rotated by [rotation] degrees
/// (clockwise on screen) about its centre, drawn with [opacity].
class LayerKey {
  const LayerKey({
    required this.t,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.rotation = 0,
    this.opacity = 1,
  });

  final double t;
  final double x, y, w, h, rotation, opacity;

  List<double> get _values => [t, x, y, w, h, rotation, opacity];

  static LayerKey _fromValues(List<double> v) => LayerKey(
    t: v[0],
    x: v[1],
    y: v[2],
    w: v[3],
    h: v[4],
    rotation: v[5],
    opacity: v[6],
  );

  Map<String, Object?> toJson() => {
    't': t,
    'x': x,
    'y': y,
    'w': w,
    'h': h,
    'rotation': rotation,
    'opacity': opacity,
  };

  @override
  String toString() =>
      'LayerKey(t: $t, x: $x, y: $y, w: $w, h: $h, '
      'rotation: $rotation, opacity: $opacity)';
}

/// A main-track clip with its absolute place on the timeline.
class PlanClip {
  const PlanClip({
    required this.id,
    required this.path,
    required this.kind,
    required this.start,
    required this.duration,
    required this.overlapIn,
    required this.sourceStart,
    required this.sourceDuration,
    required this.speed,
    required this.fit,
    required this.keys,
    required this.grade,
    required this.look,
    required this.filters,
  });

  final String id;
  final String path;
  final TimelineClipKind kind;

  /// Timeline seconds.
  final double start, duration;

  /// Seconds this clip dissolves over the previous one.
  final double overlapIn;

  /// Source seconds read: from [sourceStart] for `duration × speed`. Frame at
  /// local time `t` is source time `sourceStart + t × speed`.
  final double sourceStart, sourceDuration, speed;
  final PlanFit fit;

  /// Transform keys in local seconds; empty means identity.
  final List<TransformKey> keys;
  final RestorationSettings grade;
  final LutProfile look;
  final PlanFilters filters;

  double get end => start + duration;

  bool get isVideo => kind == TimelineClipKind.video;

  Map<String, Object?> toJson() => {
    'id': id,
    'path': path,
    'kind': kind.name,
    'start': start,
    'duration': duration,
    'overlapIn': overlapIn,
    'sourceStart': sourceStart,
    'sourceDuration': sourceDuration,
    'speed': speed,
    'fit': fit.name,
    'keys': [for (final key in keys) key.toJson()],
    'grade': grade.toJson(),
    'look': look.toJson(),
    'filters': filters.toJson(),
  };
}

/// Something drawn over the main track with alpha-over, in plan order (bottom
/// to top): an overlay, a title, an effect texture, or a colour (fades, dips,
/// strobe flashes).
class PlanLayer {
  const PlanLayer({
    required this.id,
    required this.kind,
    required this.source,
    required this.start,
    required this.duration,
    required this.keys,
    this.sourceStart = 0,
    double? sourceDuration,
    this.speed = 1,
    this.grade,
    this.look,
    this.filters = PlanFilters.none,
    this.ownerClipId,
  }) : sourceDuration = sourceDuration ?? duration;

  final String id;
  final PlanLayerKind kind;
  final PlanSource source;

  /// Timeline seconds; the layer is active for `start <= t < start + duration`.
  final double start, duration;

  /// Source seconds a video layer reads, as for [PlanClip].
  final double sourceStart, sourceDuration, speed;

  /// Keys in local seconds, sorted, at least one. The source is stretched to
  /// the rect.
  final List<LayerKey> keys;

  /// Restoration grade of a video or image layer; `null` leaves its colours.
  final RestorationSettings? grade;

  /// Creative look; `null` when there is none.
  final LutProfile? look;
  final PlanFilters filters;

  /// The main clip an effect, fade, or dip layer belongs to.
  final String? ownerClipId;

  double get end => start + duration;

  /// The native form. Generated sources need the [path] their PNG was written
  /// to and are sent as `image` layers.
  Map<String, Object?> toJson({String? path}) {
    final source = this.source;
    return {
      'id': id,
      'kind': kind.name,
      if (source is FileSource) 'path': source.path,
      if (source is GeneratedSource)
        'path':
            path ??
            (throw StateError('Generated layer $id has not been written.')),
      if (source is ColorSource) 'color': source.argb,
      'start': start,
      'duration': duration,
      'sourceStart': sourceStart,
      'sourceDuration': sourceDuration,
      'speed': speed,
      'keys': [for (final key in keys) key.toJson()],
      if (grade != null) 'grade': grade!.toJson(),
      if (look != null) 'look': look!.toJson(),
      'filters': filters.toJson(),
      if (ownerClipId != null) 'ownerClipId': ownerClipId,
    };
  }
}

/// One sound segment of the final mix. Main-clip, video-overlay, and audio
/// items all become segments, so renderers need a single audio path.
class PlanAudio {
  const PlanAudio({
    required this.id,
    required this.path,
    required this.origin,
    required this.start,
    required this.sourceStart,
    required this.sourceDuration,
    required this.speed,
    required this.volume,
    required this.fadeIn,
    required this.fadeOut,
    this.lane = 0,
  });

  /// The clip, overlay, or audio item this segment comes from.
  final String id;
  final String path;
  final PlanAudioOrigin origin;

  /// Timeline seconds.
  final double start;

  /// Source seconds read; plays for `sourceDuration / speed` timeline seconds
  /// with pitch preserved.
  final double sourceStart, sourceDuration, speed;

  /// Gain, 0…1.
  final double volume;

  /// Linear gain ramps in timeline seconds at the segment's ends.
  final double fadeIn, fadeOut;

  /// Mixer lane: segments on one lane never overlap (greedy packing in start
  /// order), so a renderer can use one track per lane.
  final int lane;

  double get duration => sourceDuration / speed;

  double get end => start + duration;

  PlanAudio _onLane(int lane) => PlanAudio(
    id: id,
    path: path,
    origin: origin,
    start: start,
    sourceStart: sourceStart,
    sourceDuration: sourceDuration,
    speed: speed,
    volume: volume,
    fadeIn: fadeIn,
    fadeOut: fadeOut,
    lane: lane,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'path': path,
    'origin': origin.name,
    'lane': lane,
    'start': start,
    'duration': duration,
    'sourceStart': sourceStart,
    'sourceDuration': sourceDuration,
    'speed': speed,
    'volume': volume,
    'fadeIn': fadeIn,
    'fadeOut': fadeOut,
  };
}

/// A [TimelineProject] resolved into absolute times, output-pixel rectangles,
/// piecewise-linear keys, colour matrices, and audio segments. Renderers and
/// the preview only execute it.
class TimelineRenderPlan {
  const TimelineRenderPlan({
    required this.width,
    required this.height,
    required this.frameRate,
    required this.duration,
    this.clips = const [],
    this.layers = const [],
    this.audio = const [],
  });

  final int width, height, frameRate;

  /// Movie length in seconds (the main track's length).
  final double duration;
  final List<PlanClip> clips;

  /// Draw order, bottom to top.
  final List<PlanLayer> layers;
  final List<PlanAudio> audio;

  /// Main clips visible at timeline time [t]: one, or the outgoing and the
  /// incoming clip during a crossfade. The movie's last instant shows the
  /// last clip.
  List<PlanClip> clipsAt(double t) {
    if (clips.isEmpty) return const [];
    final time = t.clamp(0.0, math.max(0.0, duration - 1e-9));
    return [
      for (final clip in clips)
        if (clip.start <= time && time < clip.end) clip,
    ];
  }

  /// Layers active at timeline time [t], bottom to top.
  List<PlanLayer> layersAt(double t) => [
    for (final layer in layers)
      if (layer.start <= t && t < layer.end) layer,
  ];

  /// Every distinct generated image the plan needs.
  Set<GeneratedSpec> get generatedSpecs => {
    for (final layer in layers)
      if (layer.source case GeneratedSource(:final spec)) spec,
  };

  /// Opacity of [clip] over the clip below it at timeline time [t] while it
  /// dissolves in: 0 → 1 across its overlap, else 1.
  static double dissolveAt(PlanClip clip, double t) => clip.overlapIn <= 0
      ? 1
      : ((t - clip.start) / clip.overlapIn).clamp(0.0, 1.0).toDouble();

  /// [clip]'s transform at [localT] seconds into it, linearly interpolated
  /// and clamped at the ends.
  static TransformKey evaluateClip(PlanClip clip, double localT) =>
      clip.keys.isEmpty
      ? TransformKey(t: localT)
      : TransformKey._fromValues(
          _interpolate([for (final k in clip.keys) k._values], localT),
        );

  /// [layer]'s placement at [localT] seconds into it, linearly interpolated
  /// and clamped at the ends.
  static LayerKey evaluateLayer(PlanLayer layer, double localT) =>
      LayerKey._fromValues(
        _interpolate([for (final k in layer.keys) k._values], localT),
      );

  static List<double> _interpolate(List<List<double>> keys, double t) {
    if (keys.isEmpty) throw StateError('No keys to evaluate.');
    if (t <= keys.first[0]) return [t, ...keys.first.skip(1)];
    for (var i = 1; i < keys.length; i++) {
      final b = keys[i];
      if (t <= b[0]) {
        final a = keys[i - 1];
        final span = b[0] - a[0];
        final f = span <= 0 ? 1.0 : (t - a[0]) / span;
        return [t, for (var j = 1; j < a.length; j++) a[j] + (b[j] - a[j]) * f];
      }
    }
    return [t, ...keys.last.skip(1)];
  }
}

/// Measures the width / height of a rasterised title for a canvas size; see
/// `titleAspectRatio` in `timeline_textures.dart`.
typedef TitleAspectResolver =
    double Function(TitleSpec title, int canvasWidth, int canvasHeight);

/// Compiles a [TimelineProject] into a [TimelineRenderPlan]. Pure Dart, no
/// I/O: every animation curve, rectangle, and effect parameter is resolved
/// here so every renderer and the preview agree.
abstract final class TimelineCompiler {
  /// Keys per second sampled from animated curves (every 0.1 s).
  static const samplesPerSecond = 10;

  /// Length of a strobe flash.
  static const strobeSeconds = 0.3;

  /// Sun-ray and caustic textures are larger than the canvas so rotation and
  /// drift never show their edges.
  static const sunRaysScale = 1.3;
  static const causticsScale = 1.25;

  /// Caustic drift along the diagonal, as a fraction of the canvas width per
  /// second.
  static const causticsSpeed = 0.04;

  /// Long-side caps for soft generated textures; renderers scale them up.
  static const maxSunRaysTextureSide = 1280;
  static const maxCausticsTextureSide = 1920;
  static const maxTitleTextureWidth = 4096;

  static const _slideFraction = 0.08;

  static TimelineRenderPlan compile(
    TimelineProject project, {
    TitleAspectResolver? titleAspect,
  }) {
    final (:width, :height) = project.outputSize;
    final layout = project.layout;
    final total = layout.duration;
    final entries = layout.entries;
    final clips = <PlanClip>[];
    final layers = <PlanLayer>[];
    final audio = <PlanAudio>[];

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final clip = entry.clip;
      final nextOverlap = i + 1 < entries.length
          ? entries[i + 1].overlapIn
          : 0.0;
      final speed = clip.playbackSpeed;
      final keys = motionKeys(clip, entry.duration, width, height);
      clips.add(
        PlanClip(
          id: clip.id,
          path: clip.path,
          kind: clip.kind,
          start: entry.start,
          duration: entry.duration,
          overlapIn: entry.overlapIn,
          sourceStart: clip.isVideo ? clip.sourceStart : 0,
          sourceDuration: entry.duration * speed,
          speed: speed,
          fit: keys.isEmpty ? PlanFit.contain : PlanFit.cover,
          keys: keys,
          grade: clip.grade,
          look: clip.look,
          filters: filtersFor(clip.effects, width: width, height: height),
        ),
      );
      layers.addAll(
        _clipLayers(
          project,
          entry,
          nextOverlap: nextOverlap,
          previous: i > 0 ? entries[i - 1] : null,
          width: width,
          height: height,
        ),
      );
      final fades = clip.fades;
      if (clip.isVideo && clip.gain > 0) {
        audio.add(
          PlanAudio(
            id: clip.id,
            path: clip.path,
            origin: PlanAudioOrigin.mainClip,
            start: entry.start,
            sourceStart: clip.sourceStart,
            sourceDuration: entry.duration * speed,
            speed: speed,
            volume: clip.gain,
            fadeIn: math.max(fades.fadeIn, entry.overlapIn),
            fadeOut: math.max(fades.fadeOut, nextOverlap),
          ),
        );
      }
    }

    final overlays =
        [
          for (final (index, overlay) in project.overlays.indexed)
            (index, overlay),
        ]..sort((a, b) {
          final byLane = a.$2.lane.compareTo(b.$2.lane);
          if (byLane != 0) return byLane;
          final byStart = a.$2.start.compareTo(b.$2.start);
          return byStart != 0 ? byStart : a.$1.compareTo(b.$1);
        });
    for (final (_, overlay) in overlays) {
      final start = math.max(0.0, overlay.start);
      final duration = math.min(overlay.duration, total - start);
      if (duration <= _epsilon) continue;
      final layer = _overlayLayer(
        overlay,
        start: start,
        duration: duration,
        width: width,
        height: height,
        titleAspect: titleAspect,
      );
      if (layer == null) continue;
      layers.add(layer);
      if (overlay.isVideo && overlay.gain > 0) {
        final fades = resolveFades(
          overlay.fadeIn,
          overlay.fadeOut,
          duration,
          maxSeconds: TimelineOverlay.maxFadeSeconds,
        );
        audio.add(
          PlanAudio(
            id: overlay.id,
            path: overlay.path!,
            origin: PlanAudioOrigin.overlay,
            start: start,
            sourceStart: overlay.sourceStart,
            sourceDuration: duration * overlay.playbackSpeed,
            speed: overlay.playbackSpeed,
            volume: overlay.gain,
            fadeIn: fades.fadeIn,
            fadeOut: fades.fadeOut,
          ),
        );
      }
    }

    for (final item in project.audioClips) {
      final start = math.max(0.0, item.start);
      final duration = math.min(item.duration, total - start);
      final volume = item.volume.clamp(0.0, 1.0).toDouble();
      if (duration <= _epsilon || volume <= 0) continue;
      final fades = resolveFades(
        item.fadeIn,
        item.fadeOut,
        duration,
        maxSeconds: TimelineAudioClip.maxFadeSeconds,
      );
      audio.add(
        PlanAudio(
          id: item.id,
          path: item.path,
          origin: PlanAudioOrigin.track,
          start: start,
          sourceStart: item.sourceStart,
          sourceDuration: duration,
          speed: 1,
          volume: volume,
          fadeIn: fades.fadeIn,
          fadeOut: fades.fadeOut,
        ),
      );
    }

    return TimelineRenderPlan(
      width: width,
      height: height,
      frameRate: project.frameRate,
      duration: total,
      clips: List.unmodifiable(clips),
      layers: List.unmodifiable(layers),
      audio: List.unmodifiable(packAudioLanes(audio)),
    );
  }

  /// The filters of [effects] for a [width] × [height] canvas. Colour effects
  /// multiply in list order into one matrix; repeated blurs and grains add in
  /// quadrature, repeated sharpening adds up.
  static PlanFilters filtersFor(
    Iterable<ClipEffect> effects, {
    required int width,
    required int height,
  }) {
    final unit = math.min(width, height) / 1080;
    var blur2 = 0.0, sharpen = 0.0, grain2 = 0.0;
    for (final effect in effects) {
      final i = effect.intensity;
      switch (effect.type) {
        case EffectType.softFocus:
          blur2 += math.pow(i * 6 * unit, 2);
        case EffectType.clarity:
          sharpen += i;
        case EffectType.grain:
          grain2 += math.pow(i * 0.06, 2);
        default:
          break;
      }
    }
    return PlanFilters(
      colorMatrix: ColorMatrices.combine(effects),
      blurSigma: math.sqrt(blur2),
      sharpen: sharpen,
      sharpenSigma: sharpen > 0 ? 2 * unit : 0,
      grain: math.sqrt(grain2),
    );
  }

  /// Transform keys of a main clip from its photo motion and motion effects;
  /// empty when it does not move.
  static List<TransformKey> motionKeys(
    TimelineClip clip,
    double duration,
    int width,
    int height,
  ) {
    final parts = <TransformKey Function(double t)>[];
    var animated = false;
    if (!clip.isVideo && clip.motion != ClipMotion.none) {
      final zoomIn = clip.motion == ClipMotion.zoomIn;
      parts.add((t) {
        final p = _progress(t, duration);
        return TransformKey(t: t, scale: 1 + 0.15 * (zoomIn ? p : 1 - p));
      });
    }
    for (final effect in clip.effects) {
      final i = effect.intensity;
      if (i <= 0) continue;
      switch (effect.type) {
        case EffectType.drift:
          parts.add((t) {
            final p = _progress(t, duration);
            return TransformKey(
              t: t,
              scale: 1 + 0.18 * i * p,
              x: -0.04 * width * i * p,
            );
          });
        case EffectType.swell:
          animated = true;
          final scale = swellScale(i, width, height);
          parts.add(
            (t) => TransformKey(
              t: t,
              scale: scale,
              rotation: i * 1.5 * math.sin(2 * math.pi * t / 5),
              x: i * 0.015 * width * math.sin(1.6 * math.pi * t / 5 + 0.7),
              y: i * 0.01 * height * math.sin(2.6 * math.pi * t / 5),
            ),
          );
        default:
          break;
      }
    }
    if (parts.isEmpty) return const [];
    final times = parts.length > 1 || animated
        ? _sampleTimes(duration, dense: [(0, duration)])
        : [0.0, duration];
    final keys = [
      for (final t in times)
        parts.fold(TransformKey(t: t), (sum, part) {
          final k = part(t);
          return TransformKey(
            t: t,
            scale: sum.scale * k.scale,
            x: sum.x + k.x,
            y: sum.y + k.y,
            rotation: sum.rotation + k.rotation,
          );
        }),
    ];
    final simplified = _simplify([
      for (final k in keys) k._values,
    ]).map(TransformKey._fromValues).toList();
    if (simplified.every((k) => k.isIdentity)) return const [];
    return List.unmodifiable(simplified);
  }

  /// Constant zoom of a swell with [intensity] that keeps the canvas covered
  /// at the peaks of its rotation and drift: at least `1 + 0.05·i`.
  static double swellScale(double intensity, int width, int height) {
    final theta = intensity * 1.5 * math.pi / 180;
    final a = width / 2, b = height / 2;
    final dx = intensity * 0.015 * width, dy = intensity * 0.01 * height;
    final c = math.cos(theta), s = math.sin(theta);
    final cover = math.max(
      c * (1 + dx / a) + s * (b + dy) / a,
      c * (1 + dy / b) + s * (a + dx) / b,
    );
    return math.max(1 + 0.05 * intensity, cover);
  }

  /// Height of each cinema bar: letterbox to 2.39:1 on landscape canvases,
  /// else 10 % of the height, scaled by [intensity].
  static double cinemaBarHeight(double intensity, int width, int height) =>
      width > height
      ? math.max(0, (height - width / 2.39) / 2) * intensity
      : height * 0.10 * intensity;

  /// Gives every segment the lowest lane free at its start, in start order.
  static List<PlanAudio> packAudioLanes(List<PlanAudio> segments) {
    final order = [for (var i = 0; i < segments.length; i++) i]
      ..sort((a, b) {
        final byStart = segments[a].start.compareTo(segments[b].start);
        return byStart != 0 ? byStart : a.compareTo(b);
      });
    final laneEnds = <double>[];
    final lanes = List<int>.filled(segments.length, 0);
    for (final index in order) {
      final segment = segments[index];
      var lane = laneEnds.indexWhere((end) => end <= segment.start + 1e-9);
      if (lane < 0) {
        lane = laneEnds.length;
        laneEnds.add(0);
      }
      laneEnds[lane] = segment.end;
      lanes[index] = lane;
    }
    return [
      for (var i = 0; i < segments.length; i++) segments[i]._onLane(lanes[i]),
    ];
  }

  static Iterable<PlanLayer> _clipLayers(
    TimelineProject project,
    TimelineEntry entry, {
    required double nextOverlap,
    required TimelineEntry? previous,
    required int width,
    required int height,
  }) sync* {
    final clip = entry.clip;
    final w = width.toDouble(), h = height.toDouble();
    // Clip-owned layers dissolve together with their clip.
    final visibility = [
      if (entry.overlapIn > 0)
        _Pwl([(entry.start, 0), (entry.start + entry.overlapIn, 1)]),
      if (nextOverlap > 0) _Pwl([(entry.end - nextOverlap, 1), (entry.end, 0)]),
    ];
    List<_Pwl> visibleFrom(double layerStart) => [
      for (final ramp in visibility) ramp.shifted(-layerStart),
    ];

    for (final (index, effect) in clip.effects.indexed) {
      final i = effect.intensity;
      if (i <= 0 || !effect.type.usesTexture) continue;
      final id = '${clip.id}.fx$index-${effect.type.id}';
      final duration = entry.duration;
      final vis = visibleFrom(entry.start);
      switch (effect.type) {
        case EffectType.vignette || EffectType.cinemaBars:
          yield _layer(
            id,
            clip.id,
            GeneratedSource(EffectTexture(effect.type, i, width, height)),
            entry.start,
            duration,
            _opacityKeys(duration, vis, (t, opacity) {
              return LayerKey(t: t, x: 0, y: 0, w: w, h: h, opacity: opacity);
            }),
          );
        case EffectType.sunRays:
          final rw = w * sunRaysScale, rh = h * sunRaysScale;
          final (tw, th) = _textureSize(rw, rh, maxSunRaysTextureSide);
          yield _layer(
            id,
            clip.id,
            GeneratedSource(EffectTexture(effect.type, i, tw, th)),
            entry.start,
            duration,
            _sampled(duration, (t) {
              final flicker = 0.85 + 0.15 * math.sin(2 * math.pi * t / 2.3);
              return LayerKey(
                t: t,
                x: (w - rw) / 2,
                y: (h - rh) / 2,
                w: rw,
                h: rh,
                rotation: 3 * math.sin(2 * math.pi * t / 6),
                opacity: flicker * _product(vis, t),
              );
            }),
          );
        case EffectType.caustics:
          final rw = w * causticsScale, rh = h * causticsScale;
          final (tw, th) = _textureSize(rw, rh, maxCausticsTextureSide);
          final v = causticsSpeed * w / math.sqrt2;
          yield _layer(
            id,
            clip.id,
            GeneratedSource(EffectTexture(effect.type, i, tw, th)),
            entry.start,
            duration,
            _sampled(
              duration,
              (t) => LayerKey(
                t: t,
                x: (w - rw) + _pingPong(v * t, rw - w),
                y: (h - rh) + _pingPong(v * t, rh - h),
                w: rw,
                h: rh,
                opacity: _product(vis, t),
              ),
            ),
          );
        default:
          break;
      }
    }

    for (final (index, effect) in clip.effects.indexed) {
      if (effect.type != EffectType.strobe || effect.intensity <= 0) continue;
      final duration = math.min(strobeSeconds, entry.duration);
      final i = effect.intensity;
      yield _layer(
        '${clip.id}.fx$index-strobe',
        clip.id,
        const ColorSource(0xFFFFFFFF),
        entry.start,
        duration,
        [
          for (final t in [0.0, duration])
            LayerKey(
              t: t,
              x: 0,
              y: 0,
              w: w,
              h: h,
              opacity: i * (1 - t / strobeSeconds),
            ),
        ],
      );
    }

    final fades = clip.fades;
    final color = ColorSource(clip.fadeColor.argb);
    if (fades.fadeIn > 0) {
      final d = fades.fadeIn;
      yield _layer(
        '${clip.id}.fadeIn',
        clip.id,
        color,
        entry.start,
        d,
        _opacityKeys(d, [
          _Pwl([(0, 1), (d, 0)]),
          ...visibleFrom(entry.start),
        ], (t, o) => LayerKey(t: t, x: 0, y: 0, w: w, h: h, opacity: o)),
      );
    }
    if (fades.fadeOut > 0) {
      final d = fades.fadeOut;
      yield _layer(
        '${clip.id}.fadeOut',
        clip.id,
        color,
        entry.end - d,
        d,
        _opacityKeys(d, [
          _Pwl([(0, 0), (d, 1)]),
          ...visibleFrom(entry.end - d),
        ], (t, o) => LayerKey(t: t, x: 0, y: 0, w: w, h: h, opacity: o)),
      );
    }

    if (previous != null && clip.transition.isDip) {
      final d = math.min(
        project.transitionSeconds,
        math.min(previous.duration, entry.duration) / 2,
      );
      if (d > _epsilon) {
        yield _layer(
          '${clip.id}.dip',
          clip.id,
          ColorSource(
            clip.transition == ClipTransition.dipWhite
                ? 0xFFFFFFFF
                : 0xFF000000,
          ),
          entry.start - d / 2,
          d,
          [
            for (final (t, o) in [(0.0, 0.0), (d / 2, 1.0), (d, 0.0)])
              LayerKey(t: t, x: 0, y: 0, w: w, h: h, opacity: o),
          ],
        );
      }
    }
  }

  static PlanLayer? _overlayLayer(
    TimelineOverlay overlay, {
    required double start,
    required double duration,
    required int width,
    required int height,
    required TitleAspectResolver? titleAspect,
  }) {
    final w = width.toDouble(), h = height.toDouble();
    final title = overlay.title;
    final isText = overlay.kind == OverlayKind.text;
    if (isText
        ? title == null || title.text.trim().isEmpty
        : overlay.path == null) {
      return null;
    }
    final aspect = math.max(
      0.01,
      isText && titleAspect != null
          ? titleAspect(title!, width, height)
          : overlay.mediaAspect,
    );
    final baseW =
        overlay.widthFraction
            .clamp(
              TimelineOverlay.minWidthFraction,
              TimelineOverlay.maxWidthFraction,
            )
            .toDouble() *
        w;
    final baseH = baseW / aspect;
    final opacity = overlay.opacity.clamp(0.0, 1.0).toDouble();
    final fades = resolveFades(
      overlay.fadeIn,
      overlay.fadeOut,
      duration,
      maxSeconds: TimelineOverlay.maxFadeSeconds,
    );
    final animIn = overlay.animationIn, animOut = overlay.animationOut;
    double animLength(OverlayAnimation anim, OverlayAnimation other) =>
        anim == OverlayAnimation.none
        ? 0
        : math.min(
            OverlayAnimation.seconds,
            other == OverlayAnimation.none ? duration : duration / 2,
          );
    final lIn = animLength(animIn, animOut), lOut = animLength(animOut, animIn);

    final ramps = [
      if (fades.fadeIn > 0) _Pwl([(0, 0), (fades.fadeIn, 1)]),
      if (fades.fadeOut > 0)
        _Pwl([(duration - fades.fadeOut, 1), (duration, 0)]),
      if (lIn > 0) _Pwl([(0, 0), (lIn, 1)]),
      if (lOut > 0) _Pwl([(duration - lOut, 1), (duration, 0)]),
    ];
    LayerKey at(double t) {
      var cy = overlay.centerY * h, scale = 1.0;
      if (lIn > 0 && t < lIn) {
        final p = t / lIn;
        if (animIn == OverlayAnimation.slideUp) {
          cy += _slideFraction * h * (1 - p);
        }
        if (animIn == OverlayAnimation.pop) scale *= _popScale(p);
      }
      if (lOut > 0 && t > duration - lOut) {
        final q = (t - (duration - lOut)) / lOut;
        if (animOut == OverlayAnimation.slideUp) cy -= _slideFraction * h * q;
        if (animOut == OverlayAnimation.pop) scale *= _popScale(1 - q);
      }
      final kw = baseW * scale, kh = baseH * scale;
      return LayerKey(
        t: t,
        x: overlay.centerX * w - kw / 2,
        y: cy - kh / 2,
        w: kw,
        h: kh,
        rotation: overlay.rotation,
        opacity: opacity * _product(ramps, t),
      );
    }

    final times = _sampleTimes(
      duration,
      breaks: [
        for (final ramp in ramps) ...ramp.breaks,
        if (animIn == OverlayAnimation.pop) 0.6 * lIn,
        if (animOut == OverlayAnimation.pop) duration - 0.6 * lOut,
      ],
      dense: _overlaps(ramps),
    );
    final keys = _simplifyLayerKeys([for (final t in times) at(t)]);

    final speed = overlay.playbackSpeed;
    final PlanSource source;
    final PlanLayerKind kind;
    if (isText) {
      final maxW = keys.map((k) => k.w).reduce(math.max);
      source = GeneratedSource(
        TitleTexture(
          title!,
          width: maxW.round().clamp(1, maxTitleTextureWidth),
          canvasWidth: width,
          canvasHeight: height,
        ),
      );
      kind = PlanLayerKind.image;
    } else {
      source = FileSource(overlay.path!);
      kind = overlay.isVideo ? PlanLayerKind.video : PlanLayerKind.image;
    }
    return PlanLayer(
      id: overlay.id,
      kind: kind,
      source: source,
      start: start,
      duration: duration,
      sourceStart: overlay.isVideo ? overlay.sourceStart : 0,
      sourceDuration: duration * speed,
      speed: speed,
      keys: keys,
      grade: isText ? null : overlay.grade,
      look: !isText && overlay.look.isEnabled ? overlay.look : null,
      filters: filtersFor(
        overlay.renderedEffects,
        width: width,
        height: height,
      ),
    );
  }

  /// 0.6 → 1.08 at 60 % of the animation → 1.
  static double _popScale(double p) =>
      p <= 0.6 ? 0.6 + 0.48 * p / 0.6 : 1.08 - 0.08 * (p - 0.6) / 0.4;

  static PlanLayer _layer(
    String id,
    String owner,
    PlanSource source,
    double start,
    double duration,
    List<LayerKey> keys,
  ) => PlanLayer(
    id: id,
    kind: source is ColorSource ? PlanLayerKind.color : PlanLayerKind.image,
    source: source,
    start: start,
    duration: duration,
    keys: keys,
    ownerClipId: owner,
  );

  /// Keys of a full-canvas layer whose only change is the product of [ramps].
  static List<LayerKey> _opacityKeys(
    double duration,
    List<_Pwl> ramps,
    LayerKey Function(double t, double opacity) key,
  ) {
    final times = _sampleTimes(
      duration,
      breaks: [for (final ramp in ramps) ...ramp.breaks],
      dense: _overlaps(ramps),
    );
    return _simplifyLayerKeys([
      for (final t in times) key(t, _product(ramps, t)),
    ]);
  }

  static List<LayerKey> _sampled(
    double duration,
    LayerKey Function(double) at,
  ) => _simplifyLayerKeys([
    for (final t in _sampleTimes(duration, dense: [(0, duration)])) at(t),
  ]);

  static List<LayerKey> _simplifyLayerKeys(List<LayerKey> keys) =>
      List.unmodifiable(
        _simplify([for (final k in keys) k._values]).map(LayerKey._fromValues),
      );

  static double _product(List<_Pwl> ramps, double t) =>
      ramps.fold(1.0, (value, ramp) => value * ramp.at(t));

  /// Where two of [ramps] change at once, so their product is curved and
  /// needs sampling.
  static List<(double, double)> _overlaps(List<_Pwl> ramps) => [
    for (var a = 0; a < ramps.length; a++)
      for (var b = a + 1; b < ramps.length; b++)
        if (ramps[a].varying case (final a0, final a1)?)
          if (ramps[b].varying case (final b0, final b1)?)
            if (math.min(a1, b1) - math.max(a0, b0) > _epsilon)
              (math.max(a0, b0), math.min(a1, b1)),
  ];

  /// 0 and [duration], every break inside, and every multiple of
  /// 1 / [samplesPerSecond] inside each dense range, rounded to microseconds,
  /// sorted, and without duplicates.
  static List<double> _sampleTimes(
    double duration, {
    Iterable<double> breaks = const [],
    Iterable<(double, double)> dense = const [],
  }) {
    final times = <double>[0, duration];
    for (final t in breaks) {
      if (t > 0 && t < duration) times.add(t);
    }
    for (final (a, b) in dense) {
      final from = math.max(0.0, a), to = math.min(duration, b);
      if (to - from <= _epsilon) continue;
      times
        ..add(from)
        ..add(to);
      const rate = samplesPerSecond;
      for (var k = (from * rate).ceil(); k / rate < to; k++) {
        times.add(k / rate);
      }
    }
    times.sort();
    final out = <double>[];
    for (final t in times) {
      // Whole microseconds, the finest time any renderer uses.
      final rounded = (t * 1e6).round() / 1e6;
      if (out.isEmpty || rounded - out.last > 1e-6) out.add(rounded);
    }
    return out;
  }

  /// Drops keys that lie on the line between their neighbours, and collapses
  /// a constant run to one key.
  static List<List<double>> _simplify(List<List<double>> keys) {
    final out = <List<double>>[];
    for (final key in keys) {
      while (out.length >= 2) {
        final a = out[out.length - 2], b = out.last;
        final f = (b[0] - a[0]) / (key[0] - a[0]);
        var collinear = true;
        for (var j = 1; j < key.length && collinear; j++) {
          collinear = (a[j] + (key[j] - a[j]) * f - b[j]).abs() < 1e-6;
        }
        if (!collinear) break;
        out.removeLast();
      }
      out.add(key);
    }
    if (out.length == 2) {
      var same = true;
      for (var j = 1; j < out[0].length && same; j++) {
        same = (out[0][j] - out[1][j]).abs() < 1e-6;
      }
      if (same) out.removeLast();
    }
    return out;
  }

  static double _progress(double t, double duration) =>
      duration <= 0 ? 0 : (t / duration).clamp(0.0, 1.0).toDouble();

  /// [s] bounced back and forth in `0…range`.
  static double _pingPong(double s, double range) {
    if (range <= 0) return 0;
    final m = s % (2 * range);
    return m <= range ? m : 2 * range - m;
  }

  static (int, int) _textureSize(double w, double h, int maxSide) {
    final scale = math.min(1.0, maxSide / math.max(w, h));
    return (math.max(1, (w * scale).round()), math.max(1, (h * scale).round()));
  }
}

const _epsilon = 1e-6;

/// A piecewise-linear function through sorted points, constant outside them.
class _Pwl {
  const _Pwl(this.points);

  final List<(double, double)> points;

  Iterable<double> get breaks => points.map((p) => p.$1);

  /// The range where the value changes, or `null` when it is constant.
  (double, double)? get varying {
    if (points.length < 2) return null;
    return (points.first.$1, points.last.$1);
  }

  _Pwl shifted(double dt) => _Pwl([for (final (t, v) in points) (t + dt, v)]);

  double at(double t) {
    if (t <= points.first.$1) return points.first.$2;
    for (var i = 1; i < points.length; i++) {
      final (t1, v1) = points[i];
      if (t <= t1) {
        final (t0, v0) = points[i - 1];
        return t1 - t0 <= 0 ? v1 : v0 + (v1 - v0) * (t - t0) / (t1 - t0);
      }
    }
    return points.last.$2;
  }
}
