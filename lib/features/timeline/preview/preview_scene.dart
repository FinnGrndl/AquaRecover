import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';

import '../../../core/timeline/timeline_render_plan.dart';
import '../../editor/widgets/gpu_preview_filter.dart';
import '../../editor/widgets/restored_image_preview.dart';
import '../timeline_theme.dart';
import 'preview_frame.dart';
import 'preview_grain.dart';
import 'preview_math.dart';
import 'preview_textures.dart';
import 'preview_video_pool.dart';

/// The canvas geometry at the playhead, for widgets drawn over the preview
/// (selection frames, drag handles).
class PreviewCanvas {
  const PreviewCanvas({
    required this.size,
    required this.scale,
    required this.plan,
    required this.frame,
  });

  /// Canvas size in view points.
  final Size size;

  /// View points per plan (output) pixel.
  final double scale;
  final TimelineRenderPlan plan;
  final PreviewFrame frame;

  /// The unrotated rect of the visible layer [id] in view points.
  Rect? layerRect(String id) {
    final layer = frame.layer(id);
    return layer == null ? null : PreviewGeometry.layerRect(layer.key, scale);
  }

  /// Clockwise rotation of the visible layer [id] in radians (0 if hidden).
  double layerRotation(String id) {
    final layer = frame.layer(id);
    return layer == null ? 0 : PreviewGeometry.layerRadians(layer.key);
  }

  /// A view point in plan pixels.
  Offset toPlan(Offset viewPoint) =>
      scale <= 0 ? Offset.zero : viewPoint / scale;
}

/// Builds the widgets of one [PreviewFrame]: main clips bottom to top, then
/// layers in plan order. Everything derived from a plan item (colour
/// filters, texture specs, decode widths) is memoised per item, so a frame
/// only evaluates keys and builds light widgets.
class PreviewScene {
  PreviewScene({required this.textures, required this.videos});

  final PreviewTextureCache textures;
  final PreviewVideoPool videos;

  final PreviewTextureSpecs _specs = PreviewTextureSpecs();
  final Expando<_Look> _looks = Expando('preview looks');
  final Expando<_Extent> _widths = Expando('preview widths');

  List<Widget> build({
    required PreviewFrame frame,
    required TimelineRenderPlan plan,
    required Size size,
    required double devicePixelRatio,
    required bool reduceMotion,
    required ui.Image? grainTile,
  }) {
    final scale = PreviewGeometry.scaleFor(size, plan.width);
    final grainOffset = reduceMotion
        ? Offset.zero
        : PreviewGrainMath.offsetFor(
            frame.time,
            plan.frameRate,
            PreviewGrainTile.size,
          );
    final context = _Paint(
      size: size,
      scale: scale,
      devicePixelRatio: devicePixelRatio,
      grainTile: grainTile,
      grainOffset: grainOffset,
    );
    return [
      for (final (clip, alpha) in mainClipsToDraw(
        frame.clips,
        (id) => videos.playerFor(id) != null,
      ))
        _mainClip(clip, alpha, context),
      for (final layer in frame.layers) _layer(layer, context),
    ];
  }

  /// The main clips to draw with their opacity. A crossfade draws the
  /// outgoing clip opaque under the incoming one at its dissolve alpha. When
  /// a video of the pair has no player (still opening, or over the decode
  /// budget), the other one is shown alone: a hard switch as before.
  static List<(PreviewClip, double)> mainClipsToDraw(
    List<PreviewClip> clips,
    bool Function(String id) hasFrames,
  ) {
    if (clips.isEmpty) return const [];
    if (clips.length == 1) return [(clips.single, 1)];
    final outgoing = clips[clips.length - 2], incoming = clips.last;
    bool ready(PreviewClip c) => !c.clip.isVideo || hasFrames(c.clip.id);
    if (!ready(incoming) && ready(outgoing)) return [(outgoing, 1)];
    if (!ready(outgoing)) return [(incoming, 1)];
    return [(outgoing, 1), (incoming, incoming.alpha)];
  }

  Widget _mainClip(PreviewClip item, double alpha, _Paint paint) {
    final clip = item.clip;
    Widget media;
    Rect? frameRect;
    final ColorFilter? colorFilter;
    if (clip.isVideo) {
      final player = videos.playerFor(clip.id);
      if (player == null) {
        media = _poster(opening: videos.isOpening(clip.id), main: true);
      } else {
        frameRect = PreviewGeometry.fittedRect(
          player.size,
          paint.size,
          clip.fit,
        );
        media = Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fromRect(rect: frameRect, child: player.buildView()),
          ],
        );
      }
      colorFilter = _look(
        clip,
        () => PreviewColor.combine(
          gradeBytes: GpuPreviewFilter.matrixFor(clip.grade),
          effect: clip.filters.colorMatrix,
        ),
      );
    } else {
      // The still renderer bakes the grade and look; only effects remain.
      media = RestoredImagePreview(
        key: ValueKey('photo-${clip.id}'),
        path: clip.path,
        settings: clip.grade,
        lutProfile: clip.look,
        fit: clip.fit == PlanFit.cover ? BoxFit.cover : BoxFit.contain,
        maxDimension: 1280,
      );
      colorFilter = _look(
        clip,
        () => PreviewColor.combine(effect: clip.filters.colorMatrix),
      );
    }
    media = _filtered(
      media,
      filters: clip.filters,
      colorFilter: colorFilter,
      paint: paint,
      grainRect: frameRect ?? Offset.zero & paint.size,
    );
    if (clip.keys.isNotEmpty) {
      media = Transform(
        transform: PreviewGeometry.clipMatrix(
          item.transform,
          paint.size,
          paint.scale,
        ),
        child: media,
      );
    }
    return KeyedSubtree(
      key: ValueKey('preview-clip-${clip.id}'),
      child: Opacity(
        opacity: alpha.clamp(0.0, 1.0).toDouble(),
        // The canvas is black where the frame does not reach, so a
        // letterboxed clip dissolves its bars too.
        child: ColoredBox(color: CupertinoColors.black, child: media),
      ),
    );
  }

  Widget _layer(PreviewLayer item, _Paint paint) {
    final layer = item.layer;
    final opacity = item.key.opacity.clamp(0.0, 1.0).toDouble();
    final Widget child;
    switch (layer.source) {
      case ColorSource(:final argb):
        final color = Color(argb);
        child = ColoredBox(color: color.withValues(alpha: color.a * opacity));
      case GeneratedSource(:final spec):
        final scaled = _specs.of(
          layer,
          spec,
          paint.scale * paint.devicePixelRatio,
        );
        child = PreviewTextureView(
          cache: textures,
          textureKey: scaled.key,
          spec: scaled.spec,
          opacity: opacity,
        );
      case FileSource(:final path):
        final colorFilter = _look(
          layer,
          () => PreviewColor.combine(
            gradeBytes: layer.grade == null
                ? null
                : GpuPreviewFilter.matrixFor(layer.grade!),
            effect: layer.filters.colorMatrix,
          ),
        );
        final rect = PreviewGeometry.layerRect(item.key, paint.scale);
        child = _filtered(
          layer.kind == PlanLayerKind.video
              ? _videoLayer(layer, opacity)
              : _imageLayer(layer, path, opacity, paint),
          filters: layer.filters,
          colorFilter: colorFilter,
          paint: paint,
          grainRect: Offset.zero & rect.size,
        );
    }
    return Positioned.fromRect(
      key: ValueKey('preview-layer-${layer.id}'),
      rect: PreviewGeometry.layerRect(item.key, paint.scale),
      child: Transform.rotate(
        angle: PreviewGeometry.layerRadians(item.key),
        child: child,
      ),
    );
  }

  Widget _videoLayer(PlanLayer layer, double opacity) {
    final player = videos.playerFor(layer.id);
    return Opacity(
      opacity: opacity,
      child: player == null
          ? _poster(opening: videos.isOpening(layer.id), main: false)
          : player.buildView(),
    );
  }

  Widget _imageLayer(
    PlanLayer layer,
    String path,
    double opacity,
    _Paint paint,
  ) {
    final widest = (_widths[layer] ??= _Extent(
      layer.keys.fold(0.0, (m, k) => math.max(m, k.w)),
    )).value;
    // Decode at the largest on-screen width, in steps so a resize does not
    // decode again for every pixel.
    final cacheWidth =
        (((widest * paint.scale * paint.devicePixelRatio) / 64).ceil() * 64)
            .clamp(64, 4096);
    return Image.file(
      File(path),
      key: ValueKey('preview-image-${layer.id}'),
      fit: BoxFit.fill,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      opacity: opacity < 1 ? AlwaysStoppedAnimation(opacity) : null,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }

  /// Colour (grade × effects, one matrix), then blur, then grain; the
  /// clarity sharpen is left to the export.
  Widget _filtered(
    Widget child, {
    required PlanFilters filters,
    required ColorFilter? colorFilter,
    required _Paint paint,
    required Rect grainRect,
  }) {
    var out = child;
    if (colorFilter != null) {
      out = ColorFiltered(colorFilter: colorFilter, child: out);
    }
    if (filters.blurSigma > 0) {
      final sigma = filters.blurSigma * paint.scale;
      out = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: out,
      );
    }
    final tile = paint.grainTile;
    if (filters.grain > 0 && tile != null) {
      out = Stack(
        fit: StackFit.expand,
        children: [
          out,
          Positioned.fromRect(
            rect: grainRect,
            child: IgnorePointer(
              child: CustomPaint(
                painter: PreviewGrainPainter(
                  tile: tile,
                  grain: filters.grain,
                  offset: paint.grainOffset,
                  devicePixelRatio: paint.devicePixelRatio,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return out;
  }

  ColorFilter? _look(Object item, List<double>? Function() matrix) {
    final cached = _looks[item];
    if (cached != null) return cached.filter;
    final m = matrix();
    final look = _Look(m == null ? null : ColorFilter.matrix(m));
    _looks[item] = look;
    return look.filter;
  }

  /// Stands in for a video without a player: a spinner while it opens, else
  /// a film symbol (over the decode budget, or unreadable here).
  static Widget _poster({required bool opening, required bool main}) {
    final symbol = opening
        ? const CupertinoActivityIndicator(color: TimelineColors.secondaryText)
        : Icon(
            CupertinoIcons.film,
            color: TimelineColors.secondaryText,
            size: main ? 40 : 22,
          );
    if (main) {
      return ColoredBox(
        color: CupertinoColors.black,
        child: Center(child: symbol),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x99101820),
        border: Border.all(color: TimelineColors.stroke, width: .7),
      ),
      child: Center(child: FittedBox(child: symbol)),
    );
  }
}

class _Paint {
  const _Paint({
    required this.size,
    required this.scale,
    required this.devicePixelRatio,
    required this.grainTile,
    required this.grainOffset,
  });

  final Size size;
  final double scale;
  final double devicePixelRatio;
  final ui.Image? grainTile;
  final Offset grainOffset;
}

class _Look {
  const _Look(this.filter);

  final ColorFilter? filter;
}

class _Extent {
  const _Extent(this.value);

  final double value;
}
