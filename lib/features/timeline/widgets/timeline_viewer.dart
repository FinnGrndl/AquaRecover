import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';

import '../../../core/timeline/timeline_project.dart';
import '../../../core/timeline/timeline_render_plan.dart';
import '../../../shared/reduce_motion.dart';
import '../preview/preview_audio.dart';
import '../preview/preview_frame.dart';
import '../preview/preview_grain.dart';
import '../preview/preview_player.dart';
import '../preview/preview_scene.dart';
import '../preview/preview_services.dart';
import '../preview/preview_textures.dart';
import '../preview/preview_video_pool.dart';
import '../timeline_theme.dart';

export '../preview/preview_scene.dart' show PreviewCanvas;
export '../preview/preview_services.dart' show PreviewServices;

/// Shows the compiled render plan at the playhead in the project's aspect
/// ratio: the main clip(s) with their transform, colour (grade × effects in
/// one matrix), blur, and grain; then every active layer in plan order
/// (fades, dips, flashes, effect textures, overlays, titles). Videos come
/// from a small player pool kept in sync with the playhead; audio items play
/// alongside during playback.
///
/// The plan is compiled at most once per project instance; pass [plan] (the
/// controller's cached plan) to skip that.
class TimelineViewer extends StatefulWidget {
  const TimelineViewer({
    super.key,
    required this.project,
    required this.playhead,
    required this.playing,
    this.onVideoDuration,
    this.plan,
    this.services = const PreviewServices(),
    this.canvasOverlay,
  });

  final TimelineProject project;
  final double playhead;
  final bool playing;
  final void Function(String clipId, double seconds)? onVideoDuration;

  /// The compiled plan of [project], when the caller caches one.
  final TimelineRenderPlan? plan;

  /// Players and rasteriser; the platform's by default.
  final PreviewServices services;

  /// Drawn over the canvas (selection frames, gestures), with its geometry.
  final Widget Function(BuildContext context, PreviewCanvas canvas)?
  canvasOverlay;

  /// Seconds before an item starts that its player is prepared.
  static const lookahead = 1.5;

  @override
  State<TimelineViewer> createState() => _TimelineViewerState();
}

class _TimelineViewerState extends State<TimelineViewer> {
  final _plans = PreviewPlanMemo();
  late PreviewTextureCache _textures;
  late PreviewVideoPool _videos;
  late PreviewAudioMixer _audio;
  late PreviewScene _scene;
  late PreviewPlanIndex _index;
  PreviewFrame _frame = PreviewFrame.empty;
  ui.Image? _grain;

  @override
  void initState() {
    super.initState();
    _openMedia();
    _refresh();
  }

  void _openMedia() {
    final services = widget.services;
    _textures = PreviewTextureCache(rasterize: services.rasterize);
    _videos = PreviewVideoPool(
      create: services.videoPlayerFactory,
      clock: services.clock,
      onOpened: _onOpened,
    );
    _audio = PreviewAudioMixer(
      create: services.audioPlayerFactory,
      enabled: services.playsAudio,
      lookahead: TimelineViewer.lookahead,
      clock: services.clock,
    );
    _scene = PreviewScene(textures: _textures, videos: _videos);
  }

  void _closeMedia() {
    _videos.dispose();
    _audio.dispose();
    _textures.dispose();
  }

  @override
  void didUpdateWidget(TimelineViewer old) {
    super.didUpdateWidget(old);
    if (!identical(old.services, widget.services)) {
      _closeMedia();
      _openMedia();
    } else if (identical(old.project, widget.project) &&
        identical(old.plan, widget.plan) &&
        old.playhead == widget.playhead &&
        old.playing == widget.playing) {
      return;
    }
    _refresh();
  }

  @override
  void dispose() {
    PreviewGrainTile.cancel(_onGrainReady);
    _closeMedia();
    super.dispose();
  }

  /// Evaluates the plan at the playhead and drives the players.
  void _refresh() {
    _index = _plans.resolve(widget.project, plan: widget.plan);
    _frame = PreviewFrame.at(_index.plan, widget.playhead);
    final t = _frame.time;
    final playing = widget.playing;
    final clips = _frame.clips;
    final requests = <VideoRequest>[];
    // Priority: the incoming main clip, video layers from the top, then the
    // outgoing clip of a crossfade (it falls back to a hard switch).
    if (clips.isNotEmpty && clips.last.clip.isVideo) {
      requests.add(_clipRequest(clips.last, t));
    }
    for (final layer in _frame.layers.reversed) {
      if (layer.layer.kind != PlanLayerKind.video) continue;
      if (layer.layer.source case FileSource(:final path)) {
        requests.add(
          VideoRequest(
            id: layer.layer.id,
            path: path,
            sourceTime: layer.sourceTime,
            speed: layer.layer.speed,
            volume: _index.videoGainAt(layer.layer.id, t),
          ),
        );
      }
    }
    if (clips.length > 1 && clips.first.clip.isVideo) {
      requests.add(_clipRequest(clips.first, t));
    }
    if (playing) {
      for (final item in _index.videosStartingWithin(
        t,
        TimelineViewer.lookahead,
      )) {
        requests.add(
          VideoRequest(
            id: item.id,
            path: item.path,
            sourceTime: item.sourceStart,
            visible: false,
          ),
        );
      }
    }
    _videos.update(requests, playing: playing);
    _audio.update(_index.trackAudio, t, playing: playing);
  }

  VideoRequest _clipRequest(PreviewClip clip, double t) => VideoRequest(
    id: clip.clip.id,
    path: clip.clip.path,
    sourceTime: clip.sourceTime,
    speed: clip.clip.speed,
    volume: _index.videoGainAt(clip.clip.id, t),
  );

  void _onOpened(String id, PreviewPlayer? player) {
    if (!mounted) return;
    if (player != null && _index.mainClipIds.contains(id)) {
      final seconds = player.duration.inMicroseconds / 1e6;
      final known = widget.project.clips
          .where((clip) => clip.id == id)
          .map((clip) => clip.sourceDuration)
          .firstOrNull;
      if (seconds > 0 && known != seconds) {
        widget.onVideoDuration?.call(id, seconds);
      }
    }
    setState(_refresh);
  }

  void _onGrainReady() {
    if (mounted) setState(() {});
  }

  bool get _needsGrain =>
      _frame.clips.any((c) => c.clip.filters.grain > 0) ||
      _frame.layers.any((l) => l.layer.filters.grain > 0);

  @override
  Widget build(BuildContext context) {
    final aspect =
        widget.project.aspect.widthRatio / widget.project.aspect.heightRatio;
    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: CupertinoColors.black,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: TimelineColors.stroke, width: .7),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: _canvas(context),
          ),
        ),
      ),
    );
  }

  Widget _canvas(BuildContext context) {
    if (widget.project.clips.isEmpty) return const SizedBox.expand();
    if (_frame.clips.isEmpty) {
      return const Center(
        child: Icon(
          CupertinoIcons.film,
          color: TimelineColors.secondaryText,
          size: 40,
        ),
      );
    }
    if (_needsGrain) _grain ??= PreviewGrainTile.image(onReady: _onGrainReady);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final reduceMotion = reduceMotionOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final plan = _index.plan;
        final overlay = widget.canvasOverlay;
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            ..._scene.build(
              frame: _frame,
              plan: plan,
              size: size,
              devicePixelRatio: devicePixelRatio,
              reduceMotion: reduceMotion,
              grainTile: _grain,
            ),
            if (overlay != null)
              Positioned.fill(
                child: overlay(
                  context,
                  PreviewCanvas(
                    size: size,
                    scale: plan.width <= 0 ? 0 : size.width / plan.width,
                    plan: plan,
                    frame: _frame,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
