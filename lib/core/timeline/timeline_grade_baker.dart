import 'dart:convert';
import 'dart:typed_data';

import '../processing/video_lut_baker.dart';
import 'timeline_project.dart';

/// Supplies a few downscaled, encoded frames that represent a clip.
abstract interface class ClipFrameSampler {
  Future<List<Uint8List>> framesFor(TimelineClip clip);
}

/// Bakes each clip's grade (restoration plus look) into a [ColorCube] for
/// renderers without AquaRecover shaders, caching by everything that changes
/// the result so re-exports after small edits only bake what changed.
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

  Future<ColorCube> cubeFor(TimelineClip clip) async {
    final key = cacheKey(clip);
    final cached = _cache[key];
    if (cached != null) return cached;
    final frames = await sampler.framesFor(clip);
    final cube = await VideoLutBaker.bakeFromEncodedFrames(
      frames,
      clip.grade,
      lutProfile: clip.look,
      size: cubeSize,
    );
    if (_cache.length >= 64) _cache.clear();
    return _cache[key] = cube;
  }
}
