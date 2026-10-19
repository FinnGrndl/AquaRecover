import 'dart:io';

import 'package:flutter/services.dart';

import '../processing/ffmpeg_video_backend.dart';
import '../processing/video_lut_baker.dart';
import 'ffmpeg_timeline_renderer.dart';
import 'timeline_grade_baker.dart';
import 'timeline_project.dart';

enum TimelineRenderBackend {
  /// AVAssetWriter + Core Image with the full AquaRecover grade per frame.
  apple,

  /// Media3 Transformer with baked colour tables.
  android,

  /// One ffmpeg filter graph with baked colour tables.
  ffmpeg,

  none,
}

/// Renders a [TimelineProject] to a movie with the best backend the platform
/// has, reporting progress from 0 to 1.
class TimelineRenderService {
  TimelineRenderService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('aqua_recover/timeline');

  final MethodChannel _channel;
  FfmpegTimelineRenderer? _ffmpeg;
  TimelineGradeBaker? _androidBaker;
  void Function(double progress)? _onProgress;
  bool _cancelled = false;

  static TimelineRenderBackend backendFor(
    String operatingSystem, {
    bool ffmpegAvailable = false,
  }) => switch (operatingSystem) {
    'ios' || 'macos' => TimelineRenderBackend.apple,
    'android' => TimelineRenderBackend.android,
    _ when ffmpegAvailable => TimelineRenderBackend.ffmpeg,
    _ => TimelineRenderBackend.none,
  };

  /// The backend this service renders with. Tests override it so the
  /// export flow does not depend on ffmpeg being installed.
  TimelineRenderBackend get backend => currentBackend;

  static TimelineRenderBackend get currentBackend => backendFor(
    Platform.operatingSystem,
    ffmpegAvailable:
        !Platform.isIOS &&
        !Platform.isAndroid &&
        !Platform.isMacOS &&
        FfmpegVideoBackend.locate() != null,
  );

  /// Arguments for the native renderers: each clip with its place on the
  /// timeline from [TimelineLayout], so native code never re-derives overlaps.
  static Map<String, Object?> nativeArguments(
    TimelineProject project, {
    required String outputPath,
    Map<String, ColorCube> cubes = const {},
  }) {
    final (:width, :height) = project.outputSize;
    return {
      'outputPath': outputPath,
      'width': width,
      'height': height,
      'frameRate': project.frameRate,
      'clips': [
        for (final entry in project.layout.entries)
          {
            'path': entry.clip.path,
            'kind': entry.clip.kind.name,
            'start': entry.start,
            'duration': entry.clip.duration,
            'overlapIn': entry.overlapIn,
            'sourceStart': entry.clip.sourceStart,
            'motion': entry.clip.motion.name,
            'muted': entry.clip.muted,
            'grade': entry.clip.grade.toJson(),
            'look': entry.clip.look.toJson(),
            if (cubes[entry.clip.id] case final cube?) ...{
              'lutSize': cube.size,
              'lut': cube.toArgb(),
            },
          },
      ],
    };
  }

  Future<String> render(
    TimelineProject project, {
    required String outputPath,
    void Function(double progress)? onProgress,
  }) async {
    if (project.clips.isEmpty) {
      throw StateError('Add at least one photo or clip to the timeline.');
    }
    _cancelled = false;
    final backend = this.backend;
    switch (backend) {
      case TimelineRenderBackend.none:
        throw UnsupportedError(
          'Timeline export needs iOS, macOS, Android, or ffmpeg on this computer.',
        );
      case TimelineRenderBackend.ffmpeg:
        final renderer = _ffmpeg ??= FfmpegTimelineRenderer(
          FfmpegVideoBackend(FfmpegVideoBackend.locate()!),
        );
        return renderer.render(
          project,
          outputPath: outputPath,
          onProgress: onProgress,
        );
      case TimelineRenderBackend.apple:
      case TimelineRenderBackend.android:
        final cubes = <String, ColorCube>{};
        if (backend == TimelineRenderBackend.android) {
          final baker = _androidBaker ??= TimelineGradeBaker(
            _AndroidSampler(_channel),
          );
          for (var i = 0; i < project.clips.length; i++) {
            if (_cancelled) throw const TimelineRenderCancelled();
            final clip = project.clips[i];
            cubes[clip.id] = await baker.cubeFor(clip);
            onProgress?.call(0.1 * (i + 1) / project.clips.length);
          }
          if (_cancelled) throw const TimelineRenderCancelled();
        }
        _onProgress = onProgress;
        _channel.setMethodCallHandler(_handleNativeCall);
        try {
          final path = await _channel.invokeMethod<String>(
            'renderTimeline',
            nativeArguments(project, outputPath: outputPath, cubes: cubes),
          );
          if (path == null || path.isEmpty) {
            throw StateError('The timeline render returned no file.');
          }
          return path;
        } on PlatformException catch (error) {
          if (error.code == 'CANCELLED') throw const TimelineRenderCancelled();
          throw StateError(
            'Timeline render failed. ${error.message ?? error.code}',
          );
        } finally {
          _onProgress = null;
        }
    }
  }

  void cancel() {
    _cancelled = true;
    _ffmpeg?.cancel();
    if (currentBackend
        case TimelineRenderBackend.apple || TimelineRenderBackend.android) {
      _channel.invokeMethod<void>('cancelTimeline').catchError((Object _) {});
    }
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method == 'progress' && call.arguments is num) {
      final value = (call.arguments as num).toDouble();
      final scaled = currentBackend == TimelineRenderBackend.android
          ? 0.1 + 0.9 * value
          : value;
      _onProgress?.call(scaled.clamp(0.0, 1.0));
    }
    return null;
  }
}

class _AndroidSampler implements ClipFrameSampler {
  const _AndroidSampler(this.timeline);

  final MethodChannel timeline;
  static const _video = MethodChannel('aqua_recover/video');

  @override
  Future<List<Uint8List>> framesFor(TimelineClip clip) async {
    if (!clip.isVideo) {
      final still = await timeline.invokeMethod<Uint8List>('stillFrame', {
        'path': clip.path,
        'maxDimension': VideoLutBaker.sampleMaxDimension,
      });
      if (still == null) throw StateError('Could not read ${clip.path}.');
      return [still];
    }
    final frames = await _video.invokeListMethod<Uint8List>('sampleFrames', {
      'inputPath': clip.path,
      'count': 4,
      'maxDimension': VideoLutBaker.sampleMaxDimension,
      'startSeconds': clip.sourceStart,
      'endSeconds': clip.sourceStart + clip.duration,
    });
    return frames ?? const [];
  }
}
