import 'dart:math' as math;

import '../../../core/timeline/timeline_project.dart';
import '../../../core/timeline/timeline_render_plan.dart';
import '../../../core/timeline/timeline_textures.dart';
import 'preview_math.dart';

/// A main clip as drawn at one instant.
class PreviewClip {
  const PreviewClip(
    this.clip, {
    required this.localTime,
    required this.alpha,
    required this.transform,
  });

  final PlanClip clip;

  /// Seconds into the clip.
  final double localTime;

  /// Opacity over the clips below it: 1, or the crossfade ramp of an
  /// incoming clip.
  final double alpha;
  final TransformKey transform;

  /// Source seconds of the frame shown, inside the clip's source range.
  double get sourceTime =>
      clip.sourceStart +
      (localTime * clip.speed).clamp(0.0, math.max(0.0, clip.sourceDuration));
}

/// A layer as drawn at one instant.
class PreviewLayer {
  const PreviewLayer(this.layer, {required this.localTime, required this.key});

  final PlanLayer layer;

  /// Seconds into the layer.
  final double localTime;

  /// Rect, rotation, and opacity in plan pixels.
  final LayerKey key;

  double get sourceTime =>
      layer.sourceStart +
      (localTime * layer.speed).clamp(0.0, math.max(0.0, layer.sourceDuration));
}

/// Everything visible at timeline time [time]: main clips bottom to top
/// (outgoing, then incoming during a crossfade) and active layers in plan
/// order.
class PreviewFrame {
  const PreviewFrame({
    required this.time,
    this.clips = const [],
    this.layers = const [],
  });

  static const empty = PreviewFrame(time: 0);

  final double time;
  final List<PreviewClip> clips;
  final List<PreviewLayer> layers;

  /// Evaluates [plan] at [t]. The movie's last instant shows its last frame
  /// (fades that end with the movie stay applied).
  factory PreviewFrame.at(TimelineRenderPlan plan, double t) {
    if (plan.duration <= 0) return PreviewFrame(time: t);
    final time = t.clamp(0.0, math.max(0.0, plan.duration - 1e-6)).toDouble();
    final clips = <PreviewClip>[];
    for (final clip in plan.clips) {
      if (clip.start <= time && time < clip.end) {
        final local = time - clip.start;
        clips.add(
          PreviewClip(
            clip,
            localTime: local,
            // The bottom clip is opaque; an incoming clip dissolves over it.
            alpha: clips.isEmpty
                ? 1
                : TimelineRenderPlan.dissolveAt(clip, time),
            transform: PreviewKeys.clipAt(clip.keys, local),
          ),
        );
      }
    }
    final layers = <PreviewLayer>[];
    for (final layer in plan.layers) {
      if (layer.start <= time && time < layer.end) {
        final local = time - layer.start;
        layers.add(
          PreviewLayer(
            layer,
            localTime: local,
            key: PreviewKeys.layerAt(layer.keys, local),
          ),
        );
      }
    }
    return PreviewFrame(time: time, clips: clips, layers: layers);
  }

  /// The layer with [id], if it is visible.
  PreviewLayer? layer(String id) {
    for (final layer in layers) {
      if (layer.layer.id == id) return layer;
    }
    return null;
  }
}

/// A video the preview may need to decode: a main video clip or a video
/// layer.
class PreviewVideoItem {
  const PreviewVideoItem({
    required this.id,
    required this.path,
    required this.start,
    required this.sourceStart,
    required this.isMainClip,
  });

  final String id;
  final String path;
  final double start;
  final double sourceStart;
  final bool isMainClip;
}

/// Look-ups the preview needs every frame, built once per plan.
class PreviewPlanIndex {
  PreviewPlanIndex(this.plan)
    : clipAudio = {
        for (final segment in plan.audio)
          if (segment.origin != PlanAudioOrigin.track) segment.id: segment,
      },
      trackAudio = List.unmodifiable(
        plan.audio.where((s) => s.origin == PlanAudioOrigin.track).toList()
          ..sort((a, b) => a.start.compareTo(b.start)),
      ),
      videos = List.unmodifiable(
        [
          for (final clip in plan.clips)
            if (clip.isVideo)
              PreviewVideoItem(
                id: clip.id,
                path: clip.path,
                start: clip.start,
                sourceStart: clip.sourceStart,
                isMainClip: true,
              ),
          for (final layer in plan.layers)
            if (layer.kind == PlanLayerKind.video)
              if (layer.source case FileSource(:final path))
                PreviewVideoItem(
                  id: layer.id,
                  path: path,
                  start: layer.start,
                  sourceStart: layer.sourceStart,
                  isMainClip: false,
                ),
        ]..sort((a, b) => a.start.compareTo(b.start)),
      ),
      mainClipIds = {for (final clip in plan.clips) clip.id};

  final TimelineRenderPlan plan;

  /// Sound of main video clips and video overlays, by clip or layer id; it
  /// plays through the item's own video player.
  final Map<String, PlanAudio> clipAudio;

  /// Audio items, by start; they get players of their own.
  final List<PlanAudio> trackAudio;

  /// Every video, by start, for preparing players ahead of the playhead.
  final List<PreviewVideoItem> videos;
  final Set<String> mainClipIds;

  /// Video gain of the clip or layer [id] at [t]: its volume times its fades
  /// (0 when muted or without sound).
  double videoGainAt(String id, double t) {
    final segment = clipAudio[id];
    return segment == null ? 0 : PreviewAudioMath.gainAt(segment, t);
  }

  /// Videos that start after [t] and no later than [t] + [lookahead].
  Iterable<PreviewVideoItem> videosStartingWithin(
    double t,
    double lookahead,
  ) sync* {
    for (final item in videos) {
      if (item.start > t + lookahead) break;
      if (item.start > t) yield item;
    }
  }
}

/// Compiles the plan the viewer shows at most once per project (or uses the
/// controller's cached plan when it hands one in), never per frame.
class PreviewPlanMemo {
  PreviewPlanMemo({TimelineRenderPlan Function(TimelineProject)? compile})
    : _compile = compile ?? compilePreviewPlan;

  final TimelineRenderPlan Function(TimelineProject project) _compile;
  Object? _source;
  PreviewPlanIndex? _index;

  /// How many plans were compiled; for tests.
  int compiles = 0;

  /// The index of [plan] when given, else of [project] compiled once per
  /// project instance (projects are immutable; every edit makes a new one).
  PreviewPlanIndex resolve(
    TimelineProject project, {
    TimelineRenderPlan? plan,
  }) {
    final source = plan ?? project;
    final cached = _index;
    if (cached != null && identical(source, _source)) return cached;
    final resolved = plan ?? _compileCounted(project);
    _source = source;
    return _index = PreviewPlanIndex(resolved);
  }

  TimelineRenderPlan _compileCounted(TimelineProject project) {
    compiles++;
    return _compile(project);
  }
}

/// The plan as the export compiles it: titles get the aspect of the image
/// they rasterise to, so the preview matches the movie.
TimelineRenderPlan compilePreviewPlan(TimelineProject project) =>
    TimelineCompiler.compile(project, titleAspect: titleAspectRatio);
