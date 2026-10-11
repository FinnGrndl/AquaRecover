import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/video_edit_settings.dart';
import '../processing/ffmpeg_video_backend.dart';
import 'timeline_grade_baker.dart';
import 'timeline_project.dart';

/// What the renderer needs to know about each source before building the
/// filter graph.
class ClipSourceInfo {
  const ClipSourceInfo({required this.hasAudio});

  final bool hasAudio;
}

/// Renders a [TimelineProject] with one `ffmpeg` filter graph: every clip is
/// graded with its baked `lut3d`, fitted to the output frame, and joined with
/// `concat` or `xfade`; audio follows with `concat` or `acrossfade`.
///
/// Used on Windows, where no native compositor is wired up, and by tooling.
class FfmpegTimelineRenderer {
  FfmpegTimelineRenderer(this.backend, {TimelineGradeBaker? baker})
    : baker = baker ?? TimelineGradeBaker(_FfmpegSampler(backend));

  final FfmpegVideoBackend backend;
  final TimelineGradeBaker baker;
  Process? _running;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _running?.kill();
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
    final workDir = await Directory.systemTemp.createTemp('aquarecover_tl');
    try {
      final infos = <ClipSourceInfo>[];
      for (var i = 0; i < project.clips.length; i++) {
        _throwIfCancelled();
        final clip = project.clips[i];
        final cube = await baker.cubeFor(clip);
        await cube.writeCube(p.join(workDir.path, 'clip$i.cube'));
        infos.add(
          ClipSourceInfo(
            hasAudio: clip.isVideo && (await backend.probe(clip.path)).hasAudio,
          ),
        );
        onProgress?.call(0.15 * (i + 1) / project.clips.length);
      }
      _throwIfCancelled();
      final args = buildArguments(
        project,
        infos,
        outputPath: p.absolute(outputPath),
      );
      final process = await Process.start(
        backend.ffmpeg,
        args,
        workingDirectory: workDir.path,
      );
      _running = process;
      final total = project.duration;
      final progressDone = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) {
            final micros = parseProgressMicros(line);
            if (micros != null && total > 0) {
              onProgress?.call(
                0.15 + 0.85 * (micros / 1e6 / total).clamp(0.0, 1.0),
              );
            }
          });
      final log = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode;
      await progressDone;
      _running = null;
      _throwIfCancelled();
      if (exitCode != 0) {
        throw StateError(
          'Timeline render failed with FFmpeg exit $exitCode. '
          '${FfmpegVideoBackend.redactLog(await log, project.clips.first.path, outputPath)}',
        );
      }
      onProgress?.call(1);
      return outputPath;
    } finally {
      _running = null;
      await workDir.delete(recursive: true);
    }
  }

  void _throwIfCancelled() {
    if (_cancelled) throw const TimelineRenderCancelled();
  }

  /// `out_time_us=` (or the older, misnamed `out_time_ms=`) from
  /// `-progress pipe:1`, in microseconds.
  static int? parseProgressMicros(String line) {
    final match = RegExp(r'^out_time_[mu]s=(\d+)').firstMatch(line.trim());
    return match == null ? null : int.parse(match.group(1)!);
  }

  /// The full ffmpeg argument list. Clip `i` reads its colour table from
  /// `clip$i.cube` in the working directory.
  static List<String> buildArguments(
    TimelineProject project,
    List<ClipSourceInfo> infos, {
    required String outputPath,
  }) {
    final (:width, :height) = project.outputSize;
    final fps = project.frameRate;
    final layout = project.layout;
    String n(double v) => v.toStringAsFixed(3);

    final inputs = <String>[];
    final graph = <String>[];
    for (final entry in layout.entries) {
      final clip = entry.clip;
      final i = entry.index;
      final d = n(clip.duration);
      if (clip.isVideo) {
        inputs.addAll([
          if (clip.sourceStart > 0) ...['-ss', n(clip.sourceStart)],
          '-t',
          d,
          '-i',
          clip.path,
        ]);
      } else {
        inputs.addAll([
          '-loop',
          '1',
          '-framerate',
          '$fps',
          '-t',
          d,
          '-i',
          clip.path,
        ]);
      }

      final lut = 'lut3d=file=clip$i.cube:interp=tetrahedral';
      final tail =
          'setsar=1,fps=$fps,format=yuv420p,settb=AVTB,'
          'setpts=PTS-STARTPTS';
      if (!clip.isVideo && clip.motion != ClipMotion.none) {
        final frames = (clip.duration * fps).round().clamp(1, 1 << 20);
        final zoom = clip.motion == ClipMotion.zoomIn
            ? '1+0.15*on/$frames'
            : '1.15-0.15*on/$frames';
        graph.add(
          '[$i:v]scale=${width * 2}:${height * 2}:'
          'force_original_aspect_ratio=increase,'
          'crop=${width * 2}:${height * 2},'
          "zoompan=z='$zoom':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'"
          ':d=1:s=${width}x$height:fps=$fps,'
          '$lut,$tail[v$i]',
        );
      } else {
        graph.add(
          '[$i:v]scale=$width:$height:force_original_aspect_ratio=decrease,'
          '$lut,pad=$width:$height:(ow-iw)/2:(oh-ih)/2:color=black,'
          '$tail[v$i]',
        );
      }

      if (clip.isVideo && !clip.muted && infos[i].hasAudio) {
        graph.add(
          '[$i:a]aformat=sample_rates=48000:channel_layouts=stereo,'
          'apad,atrim=0:$d,asetpts=PTS-STARTPTS[a$i]',
        );
      } else {
        graph.add('anullsrc=r=48000:cl=stereo,atrim=0:$d[a$i]');
      }
    }

    var video = 'v0';
    var audio = 'a0';
    for (final entry in layout.entries.skip(1)) {
      final i = entry.index;
      if (entry.overlapIn > 0) {
        graph
          ..add(
            '[$video][v$i]xfade=transition=fade:'
            'duration=${n(entry.overlapIn)}:offset=${n(entry.start)}[vx$i]',
          )
          ..add('[$audio][a$i]acrossfade=d=${n(entry.overlapIn)}[ax$i]');
      } else {
        graph
          ..add('[$video][v$i]concat=n=2:v=1:a=0[vx$i]')
          ..add('[$audio][a$i]concat=n=2:v=0:a=1[ax$i]');
      }
      video = 'vx$i';
      audio = 'ax$i';
    }

    return [
      '-hide_banner',
      '-nostdin',
      '-y',
      '-progress',
      'pipe:1',
      '-nostats',
      ...inputs,
      '-filter_complex',
      graph.join(';'),
      '-map',
      '[$video]',
      '-map',
      '[$audio]',
      '-c:v',
      'libx264',
      '-preset',
      'medium',
      '-crf',
      '18',
      '-pix_fmt',
      'yuv420p',
      '-r',
      '$fps',
      '-c:a',
      'aac',
      '-b:a',
      '192k',
      '-map_metadata',
      '-1',
      '-movflags',
      '+faststart',
      outputPath,
    ];
  }
}

class TimelineRenderCancelled implements Exception {
  const TimelineRenderCancelled();

  @override
  String toString() => 'Timeline render was cancelled.';
}

class _FfmpegSampler implements ClipFrameSampler {
  const _FfmpegSampler(this.backend);

  final FfmpegVideoBackend backend;

  @override
  Future<List<Uint8List>> framesFor(TimelineClip clip) async {
    if (!clip.isVideo) return [await backend.stillFrame(clip.path)];
    return backend.sampleFrames(
      clip.path,
      trim: VideoEditSettings(
        enabled: true,
        startSeconds: clip.sourceStart,
        endSeconds: clip.sourceEnd,
      ),
    );
  }
}
