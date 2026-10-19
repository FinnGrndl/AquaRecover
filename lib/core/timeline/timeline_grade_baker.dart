import 'dart:convert';
import 'dart:typed_data';

import '../models/lut_profile.dart';
import '../models/restoration_settings.dart';
import '../processing/video_lut_baker.dart';
import 'timeline_project.dart';
import 'timeline_render_plan.dart';

/// Supplies a few downscaled, encoded frames that represent a clip.
abstract interface class ClipFrameSampler {
  Future<List<Uint8List>> framesFor(TimelineClip clip);
}

/// Bakes each clip's grade (restoration plus look) into a [ColorCube] for
/// renderers without AquaRecover shaders, caching by everything that changes
/// the result so re-exports after small edits only bake what changed.
///
/// A colour-effect matrix is applied to the cached grade cube afterwards
/// (`cube' = M(cube)`, clamped to 0…1), so changing an effect never re-samples
/// frames.
class TimelineGradeBaker {
  TimelineGradeBaker(this.sampler, {this.cubeSize = VideoLutBaker.defaultSize});

  final ClipFrameSampler sampler;
  final int cubeSize;
  final Map<String, ColorCube> _cache = {};

  static String cacheKey(TimelineClip clip) => jsonEncode([
    clip.path,
    clip.sourceStart,
    clip.sourceEnd,
    clip.grade.toJson(),
    clip.look.toJson(),
  ]);

  /// [clip]'s grade and look, then [colorMatrix] (a [ColorMatrices] 4×5
  /// matrix) when given.
  Future<ColorCube> cubeFor(
    TimelineClip clip, {
    List<double>? colorMatrix,
  }) async {
    final key = cacheKey(clip);
    var cube = _cache[key];
    if (cube == null) {
      final frames = await sampler.framesFor(clip);
      cube = await VideoLutBaker.bakeFromEncodedFrames(
        frames,
        clip.grade,
        lutProfile: clip.look,
        size: cubeSize,
      );
      if (_cache.length >= 64) _cache.clear();
      _cache[key] = cube;
    }
    return colorMatrix == null ? cube : applyColorMatrix(cube, colorMatrix);
  }

  /// The cube of a video or image [layer]: its grade and look, then its
  /// colour matrix. A layer with only a matrix gets it on an identity cube
  /// without sampling frames; `null` when the layer needs no colour table.
  Future<ColorCube?> cubeForLayer(PlanLayer layer) async {
    final source = layer.source;
    if (source is! FileSource) return null;
    final matrix = layer.filters.colorMatrix;
    final grade = layer.grade, look = layer.look;
    if (grade == null && (look == null || !look.isEnabled)) {
      return matrix == null
          ? null
          : applyColorMatrix(identityCube(cubeSize), matrix);
    }
    final isVideo = layer.kind == PlanLayerKind.video;
    return cubeFor(
      TimelineClip(
        id: layer.id,
        path: source.path,
        kind: isVideo ? TimelineClipKind.video : TimelineClipKind.image,
        sourceStart: layer.sourceStart,
        sourceEnd: isVideo ? layer.sourceStart + layer.sourceDuration : null,
        grade: grade ?? RestorationPreset.none.settings,
        look: look ?? LutProfile.none,
      ),
      colorMatrix: matrix,
    );
  }

  /// A cube that maps every colour to itself.
  static ColorCube identityCube(int size) {
    final rgb = Uint8List(size * size * size * 3);
    var j = 0;
    int level(int i) => (i * 255 / (size - 1)).round();
    for (var b = 0; b < size; b++) {
      for (var g = 0; g < size; g++) {
        for (var r = 0; r < size; r++) {
          rgb[j++] = level(r);
          rgb[j++] = level(g);
          rgb[j++] = level(b);
        }
      }
    }
    return ColorCube(size, rgb);
  }

  /// [cube] followed by the 4×5 [matrix] (offsets in 0…1, alpha taken as 1),
  /// clamped to 0…1.
  static ColorCube applyColorMatrix(ColorCube cube, List<double> matrix) {
    if (matrix.length != 20) {
      throw ArgumentError.value(matrix.length, 'matrix', 'must hold 20 values');
    }
    final src = cube.rgb;
    final out = Uint8List(src.length);
    int channel(int row, double r, double g, double b) {
      final m = row * 5;
      final v =
          matrix[m] * r +
          matrix[m + 1] * g +
          matrix[m + 2] * b +
          matrix[m + 3] +
          matrix[m + 4];
      return (v.clamp(0.0, 1.0) * 255).round();
    }

    for (var j = 0; j < src.length; j += 3) {
      final r = src[j] / 255, g = src[j + 1] / 255, b = src[j + 2] / 255;
      out[j] = channel(0, r, g, b);
      out[j + 1] = channel(1, r, g, b);
      out[j + 2] = channel(2, r, g, b);
    }
    return ColorCube(cube.size, out);
  }
}
