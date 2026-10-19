import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/video_edit_settings.dart';
import '../processing/ffmpeg_video_backend.dart';
import 'timeline_grade_baker.dart';
import 'timeline_project.dart';
import 'timeline_render_plan.dart';

/// Everything one ffmpeg run needs: the argument list, the filter graph
/// (written to [FfmpegTimelineRenderer.graphFileName] in the working
/// directory and loaded from there, so long graphs never hit command-line
/// limits), and the `sendcmd` scripts the graph reads, by file name.
class FfmpegTimelineJob {
  const FfmpegTimelineJob({
    required this.arguments,
    required this.graph,
    this.scripts = const {},
  });

  final List<String> arguments;
  final String graph;
  final Map<String, String> scripts;
}

/// Renders a [TimelineRenderPlan] with one `ffmpeg` filter graph, with the
/// same semantics as the Apple and Android renderers:
///
/// - **Main clips** are trimmed (`-ss`/`-t`), retimed (`setpts`), normalised
///   to the plan's frame rate and an exact frame count, fitted (`scale` with
///   `force_original_aspect_ratio`), graded by their baked `lut3d` cube (grade,
///   look, and colour matrix), filtered (`gblur`, `unsharp`, luma `noise`),
///   and placed: `pad` for a still contain fit, `perspective` driven by
///   piecewise-linear expressions of the frame number for transform keys.
///   They are joined with `concat` (cuts and dips) or `xfade` (crossfades).
/// - **Layers** follow in plan order, each `overlay`ed with
///   `eof_action=pass` and an `enable` window: images are decoded once and
///   looped, videos retimed like clips, colours come from `color`. Their keys
///   become `scale` (`eval=frame`), `rotate`, and overlay `x`/`y` expressions
///   of `t`; opacity runs through `colorchannelmixer`, from a `sendcmd`
///   script when it changes.
/// - **Audio** segments are retimed with `atempo`, padded to their exact
///   sample length, given volume and `afade` ramps, packed per lane with
///   `adelay` + `concat`, and mixed with `amix` (`normalize=0`) and `alimiter`
///   into AAC.
///
/// Compositing happens in planar RGB (`gbrp`), the plan's gamma-encoded RGB;
/// sharpening and grain run in a full-range BT.709 YUV round trip so the
/// grain stays monochrome. Output is H.264 4:2:0 tagged BT.709.
///
/// Used on Windows and Linux, where no native compositor is wired up.
class FfmpegTimelineRenderer {
  FfmpegTimelineRenderer(this.backend, {TimelineGradeBaker? baker})
    : baker = baker ?? TimelineGradeBaker(_FfmpegSampler(backend));

  final FfmpegVideoBackend backend;
  final TimelineGradeBaker baker;
  Process? _running;
  bool _cancelled = false;

  /// The filter graph's file name in the working directory.
  static const graphFileName = 'graph.txt';

  /// Output audio sample rate.
  static const sampleRate = 48000;

  static final Map<String, String> _graphOptions = {};

  void cancel() {
    _cancelled = true;
    _running?.kill();
  }

  /// Renders [plan], compiled from [project]; [generatedPaths] are the PNGs
  /// of generated title and texture layers by layer id (see
  /// `TimelineRenderService.writeGeneratedSources`).
  Future<String> render(
    TimelineProject project, {
    required TimelineRenderPlan plan,
    required String outputPath,
    Map<String, String> generatedPaths = const {},
    void Function(double progress)? onProgress,
  }) async {
    if (plan.clips.isEmpty) {
      throw StateError('Add at least one photo or clip to the timeline.');
    }
    _cancelled = false;
    final workDir = await Directory.systemTemp.createTemp('aquarecover_tl');
    try {
      final clips = {for (final clip in project.clips) clip.id: clip};
      final cubeFiles = <String, String>{};
      final fileLayers = plan.layers.where((l) => l.source is FileSource);
      final steps = plan.clips.length + fileLayers.length + 1;
      var done = 0;
      void step() => onProgress?.call(0.15 * ++done / steps);
      for (final (i, planClip) in plan.clips.indexed) {
        _throwIfCancelled();
        final cube = await baker.cubeFor(
          clips[planClip.id]!,
          colorMatrix: planClip.filters.colorMatrix,
        );
        final name = 'c$i.cube';
        await cube.writeCube(p.join(workDir.path, name));
        cubeFiles[planClip.id] = name;
        step();
      }
      for (final (j, layer) in plan.layers.indexed) {
        if (layer.source is! FileSource) continue;
        _throwIfCancelled();
        if (await baker.cubeForLayer(layer) case final cube?) {
          final name = 'l$j.cube';
          await cube.writeCube(p.join(workDir.path, name));
          cubeFiles[layer.id] = name;
        }
        step();
      }
      final withAudio = <String>{};
      for (final path in {for (final segment in plan.audio) segment.path}) {
        _throwIfCancelled();
        try {
          if ((await backend.probe(path)).hasAudio) withAudio.add(path);
        } on Object {
          // An unreadable file simply contributes no sound.
        }
      }
      step();
      _throwIfCancelled();

      final job = buildArguments(
        plan,
        outputPath: p.absolute(outputPath),
        generatedPaths: generatedPaths,
        cubeFiles: cubeFiles,
        hasAudio: withAudio.contains,
        graphOption: await _graphOption(),
      );
      await File(
        p.join(workDir.path, graphFileName),
      ).writeAsString(job.graph, flush: true);
      for (final MapEntry(:key, :value) in job.scripts.entries) {
        await File(p.join(workDir.path, key)).writeAsString(value, flush: true);
      }
      _throwIfCancelled();

      final process = await Process.start(
        backend.ffmpeg,
        job.arguments,
        workingDirectory: workDir.path,
      );
      _running = process;
      final total = plan.duration;
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
          '${FfmpegVideoBackend.redactLog(await log, plan.clips.first.path, outputPath)}',
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

  Future<String> _graphOption() async {
    final cached = _graphOptions[backend.ffmpeg];
    if (cached != null) return cached;
    var banner = '';
    try {
      final result = await Process.run(backend.ffmpeg, const [
        '-hide_banner',
        '-version',
      ], stdoutEncoding: utf8);
      banner = result.stdout as String;
    } on Object {
      // Fall back to the option every version up to 7.x understands.
    }
    return _graphOptions[backend.ffmpeg] = graphOptionFor(banner);
  }

  /// How to load the filter graph from a file: `-/filter_complex` from
  /// FFmpeg 7 (libavfilter 10), which deprecates `-filter_complex_script`;
  /// the latter before, and when [versionBanner] (`ffmpeg -version`) does not
  /// say.
  static String graphOptionFor(String versionBanner) {
    final match = RegExp(r'libavfilter\s+(\d+)\.').firstMatch(versionBanner);
    final major = match == null ? 0 : int.parse(match.group(1)!);
    return major >= 10 ? '-/filter_complex' : '-filter_complex_script';
  }

  /// `out_time_us=` (or the older, misnamed `out_time_ms=`) from
  /// `-progress pipe:1`, in microseconds.
  static int? parseProgressMicros(String line) {
    final match = RegExp(r'^out_time_[mu]s=(\d+)').firstMatch(line.trim());
    return match == null ? null : int.parse(match.group(1)!);
  }

  /// The ffmpeg job for [plan]. Pure: no I/O.
  ///
  /// [generatedPaths] are the PNGs of generated layers by layer id;
  /// [cubeFiles] the `.cube` file names (in the working directory) by clip or
  /// layer id; [hasAudio] tells whether a source path has an audio stream
  /// (segments of silent files are skipped); [graphOption] is the option
  /// that loads [graphFileName] (see [graphOptionFor]).
  static FfmpegTimelineJob buildArguments(
    TimelineRenderPlan plan, {
    required String outputPath,
    Map<String, String> generatedPaths = const {},
    Map<String, String> cubeFiles = const {},
    bool Function(String path)? hasAudio,
    String graphOption = '-filter_complex_script',
  }) => _GraphBuilder(
    plan,
    generatedPaths: generatedPaths,
    cubeFiles: cubeFiles,
    hasAudio: hasAudio ?? (_) => true,
  ).build(outputPath: outputPath, graphOption: graphOption);
}

class TimelineRenderCancelled implements Exception {
  const TimelineRenderCancelled();

  @override
  String toString() => 'Timeline render was cancelled.';
}

/// Builds the filter graph of one plan.
class _GraphBuilder {
  _GraphBuilder(
    this.plan, {
    required this.generatedPaths,
    required this.cubeFiles,
    required this.hasAudio,
  }) : fps = plan.frameRate,
       width = plan.width,
       height = plan.height,
       totalFrames = math.max(1, _frameAt(plan.duration, plan.frameRate));

  final TimelineRenderPlan plan;
  final Map<String, String> generatedPaths;
  final Map<String, String> cubeFiles;
  final bool Function(String path) hasAudio;
  final int fps, width, height, totalFrames;

  final inputs = <String>[];
  final graph = <String>[];
  final scripts = <String, String>{};
  var _inputCount = 0;

  /// First output frame at or after timeline second [t].
  static int _frameAt(double t, int fps) => (t * fps - 1e-6).ceil();

  int frameAt(double t) => _frameAt(t, fps).clamp(0, totalFrames);

  int addInput(List<String> args) {
    inputs.addAll(args);
    return _inputCount++;
  }

  FfmpegTimelineJob build({
    required String outputPath,
    required String graphOption,
  }) {
    var video = _mainTrack();
    for (final (j, layer) in plan.layers.indexed) {
      video = _layer(j, layer, video) ?? video;
    }
    graph.add(
      '[$video]scale=out_color_matrix=bt709:out_range=tv,'
      'format=yuv420p[vout]',
    );
    _audio();
    return FfmpegTimelineJob(
      graph: '${graph.join(';\n')}\n',
      scripts: scripts,
      arguments: [
        '-hide_banner',
        '-nostdin',
        '-y',
        '-progress',
        'pipe:1',
        '-nostats',
        ...inputs,
        graphOption,
        FfmpegTimelineRenderer.graphFileName,
        '-map',
        '[vout]',
        '-map',
        '[aout]',
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
        '-colorspace',
        'bt709',
        '-color_primaries',
        'bt709',
        '-color_trc',
        'bt709',
        '-color_range',
        'tv',
        '-c:a',
        'aac',
        '-b:a',
        '192k',
        '-ar',
        '${FfmpegTimelineRenderer.sampleRate}',
        '-map_metadata',
        '-1',
        '-movflags',
        '+faststart',
        outputPath,
      ],
    );
  }

  // ---------------------------------------------------------------- clips --

  /// Every main clip as an exact run of output frames, joined in order.
  /// Returns the label of the joined track.
  String _mainTrack() {
    String? track;
    var trackEnd = 0;
    for (final (i, clip) in plan.clips.indexed) {
      final a = math.min(frameAt(clip.start), totalFrames - 1);
      final b = math.max(a + 1, frameAt(clip.end));
      final label = _clip(i, clip, a, b - a);
      if (track == null) {
        track = label;
      } else {
        final overlap = trackEnd - a;
        if (overlap > 0) {
          graph.add(
            '[$track][$label]xfade=transition=fade:'
            'duration=${_n(overlap / fps)}:offset=${_n(a / fps)}[mx$i]',
          );
        } else {
          graph.add('[$track][$label]concat=n=2:v=1:a=0[mx$i]');
        }
        track = 'mx$i';
      }
      trackEnd = math.max(trackEnd, b);
    }
    return track!;
  }

  /// Clip [i] as [frames] frames from output frame [a], in `gbrp` at the
  /// canvas size, time base 1/fps, and pts from 0.
  String _clip(int i, PlanClip clip, int a, int frames) {
    final delta = a / fps - clip.start;
    final filters = clip.filters;
    final fitMode = clip.fit == PlanFit.cover ? 'increase' : 'decrease';
    final fit = [
      'scale=$width:$height:force_original_aspect_ratio=$fitMode:'
          'force_divisible_by=2:flags=bicubic',
      'setsar=1',
      'format=gbrp',
      if (cubeFiles[clip.id] case final cube?)
        'lut3d=file=$cube:interp=tetrahedral',
      if (filters.blurSigma > 0) 'gblur=sigma=${_n(filters.blurSigma)}',
      if (_sharpen(filters) case final sharpen?) _yuv(sharpen, alpha: false),
    ];
    final grain = _grain(filters);
    final geometry = _clipGeometry(clip, delta);
    final timing = 'trim=end_frame=$frames,settb=1/$fps,setpts=N';
    final List<String> chain;
    if (clip.isVideo) {
      final input = addInput([
        '-ss',
        _n(clip.sourceStart + delta * clip.speed),
        '-t',
        _n(clip.sourceDuration + clip.speed / fps),
        '-i',
        clip.path,
      ]);
      chain = [
        '[$input:v]${_retime(clip.speed)}',
        'fps=$fps',
        'tpad=stop=-1:stop_mode=clone',
        timing,
        ...fit,
        if (grain != null) _yuv(grain, alpha: false),
        ...geometry.still,
        ...geometry.moving,
      ];
    } else {
      final input = addInput(['-i', clip.path]);
      chain = [
        '[$input:v]${fit.first}',
        ...fit.skip(1),
        ...geometry.still,
        'loop=loop=-1:size=1',
        timing,
        if (grain != null) _yuv(grain, alpha: false),
        ...geometry.moving,
      ];
    }
    graph.add('${chain.join(',')}[m$i]');
    return 'm$i';
  }

  /// Placement of a fitted clip frame: a black `pad` (contain) or a centred
  /// `crop` (cover) when it does not move, else `perspective` mapping the
  /// frame's corners to where the keys put them. [still] filters run once
  /// per photo, [moving] ones on every frame.
  ({List<String> still, List<String> moving}) _clipGeometry(
    PlanClip clip,
    double delta,
  ) {
    if (clip.keys.isEmpty) {
      return (
        still: [
          if (clip.fit == PlanFit.cover)
            'crop=$width:$height'
          else
            'pad=$width:$height:(ow-iw)/2:(oh-ih)/2:color=black',
        ],
        moving: const [],
      );
    }
    final margin = _revealMargin(clip.keys);
    final edge = margin + 2;
    final w = width + 2 * edge, h = height + 2 * edge;
    final prep = [
      "crop=w='min(iw,${width + 2 * margin})':"
          "h='min(ih,${height + 2 * margin})'",
      'pad=$w:$h:(ow-iw)/2:(oh-ih)/2:color=black',
    ];
    // Corners of the padded frame relative to its centre (the canvas
    // centre): top-left, top-right, bottom-left, bottom-right.
    const corners = [(-1, -1), (1, -1), (-1, 1), (1, 1)];
    final points = [for (var c = 0; c < 8; c++) <(double, double)>[]];
    for (final key in clip.keys) {
      // `in` is 1 on a clip's first frame, which shows local time delta.
      final frame = (key.t - delta) * fps + 1;
      final angle = key.rotation * math.pi / 180;
      final cos = math.cos(angle) * key.scale;
      final sin = math.sin(angle) * key.scale;
      for (final (c, (sx, sy)) in corners.indexed) {
        final dx = sx * w / 2, dy = sy * h / 2;
        points[2 * c].add((frame, w / 2 + key.x + dx * cos - dy * sin));
        points[2 * c + 1].add((frame, h / 2 + key.y + dx * sin + dy * cos));
      }
    }
    final pwl = [for (final list in points) _Pwl(list)];
    final still = pwl.every((f) => f.isConstant);
    const names = ['x0', 'y0', 'x1', 'y1', 'x2', 'y2', 'x3', 'y3'];
    final corner = [
      for (final (k, f) in pwl.indexed) "${names[k]}='${f.expression('in')}'",
    ];
    final perspective =
        'perspective=${corner.join(':')}:sense=destination:'
        'interpolation=cubic:eval=${still ? 'init' : 'frame'},'
        'crop=$width:$height:$edge:$edge';
    return still
        ? (still: [...prep, perspective], moving: const [])
        : (still: prep, moving: [perspective]);
  }

  /// Pixels beyond the canvas (around the centred fitted frame) that [keys]
  /// bring into view, rounded up to an even number; 0 for ordinary motion,
  /// which keeps the canvas covered.
  int _revealMargin(List<TransformKey> keys) {
    var excess = 0.0;
    for (final key in keys) {
      final angle = key.rotation * math.pi / 180;
      final cos = math.cos(angle), sin = math.sin(angle);
      for (final (cx, cy) in [
        (-width / 2, -height / 2),
        (width / 2, -height / 2),
        (-width / 2, height / 2),
        (width / 2, height / 2),
      ]) {
        final dx = (cx - key.x) / key.scale, dy = (cy - key.y) / key.scale;
        // The canvas corner rotated back into the fitted frame.
        final qx = dx * cos + dy * sin, qy = -dx * sin + dy * cos;
        excess = math.max(
          excess,
          math.max(qx.abs() - width / 2, qy.abs() - height / 2),
        );
      }
    }
    if (excess <= 0.5) return 0;
    final margin = math.min(excess.ceil() + 2, math.max(width, height));
    return margin.isOdd ? margin + 1 : margin;
  }

  // --------------------------------------------------------------- layers --

  /// Overlays layer [j] onto [below]; returns the new label, or `null` when
  /// the layer shows on no output frame.
  String? _layer(int j, PlanLayer layer, String below) {
    final a = frameAt(layer.start);
    final b = frameAt(layer.end);
    final frames = b - a;
    if (frames <= 0) return null;
    final keys = layer.keys;
    double most(double Function(LayerKey k) f) => keys.map(f).reduce(math.max);
    final sw = math.max(1, most((k) => k.w).round());
    final sh = math.max(1, most((k) => k.h).round());
    // Keys in timeline seconds, as `t` in the graph is.
    _Pwl field(double Function(LayerKey k) f) =>
        _Pwl([for (final k in keys) (layer.start + k.t, f(k))]);
    final w = field((k) => k.w), h = field((k) => k.h);
    final rotation = field((k) => k.rotation);
    final opacity = field((k) => k.opacity.clamp(0.0, 1.0));
    final centerX = field((k) => k.x + k.w / 2);
    final centerY = field((k) => k.y + k.h / 2);
    final sizeStill = w.isConstant && h.isConstant;
    final rotates = !(rotation.isConstant && rotation.first.abs() < 1e-9);
    final side = math.sqrt(sw * sw + sh * sh).ceil() + 2;
    final rotate = rotates
        ? "rotate=a='(${rotation.expression('t')})*PI/180':"
              'ow=$side:oh=$side:c=black@0'
        : null;
    final scripted = !opacity.isConstant;
    final alpha = scripted
        ? 'sendcmd=f=l$j.cmd,colorchannelmixer@l$j=aa=${_n(opacity.first)}'
        : (opacity.first < 1 - 1e-9
              ? 'colorchannelmixer=aa=${_n(opacity.first)}'
              : null);
    if (scripted) scripts['l$j.cmd'] = _opacityScript(j, layer.id, opacity);

    final filters = layer.filters;
    final look = [
      if (cubeFiles[layer.id] case final cube?)
        'lut3d=file=$cube:interp=tetrahedral',
    ];
    final size = [
      'scale=$sw:$sh:flags=bicubic',
      'setsar=1',
      if (filters.blurSigma > 0)
        'gblur=sigma=${_n(filters.blurSigma)}:planes=7',
      if (_sharpen(filters) case final sharpen?) _yuv(sharpen, alpha: true),
    ];
    final grain = _grain(filters);
    final timing = 'trim=end_frame=$frames,settb=1/$fps,setpts=N+$a';
    final moving = [
      if (grain != null) _yuv(grain, alpha: true),
      if (!sizeStill)
        "scale=w='max(1,round(${w.expression('t')}))':"
            "h='max(1,round(${h.expression('t')}))':eval=frame:flags=bicubic",
    ];

    final List<String> chain;
    switch (layer.source) {
      case ColorSource(:final argb):
        final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
        final colorAlpha = ((argb >> 24) & 0xFF) / 255;
        chain = [
          'color=c=0x$rgb@${_n(colorAlpha)}:s=${sw}x$sh:r=$fps',
          'format=gbrap',
          timing,
          ?alpha,
          ...moving,
          ?rotate,
        ];
      case FileSource() || GeneratedSource()
          when layer.kind == PlanLayerKind.video:
        final delta = a / fps - layer.start;
        final input = addInput([
          '-ss',
          _n(layer.sourceStart + delta * layer.speed),
          '-t',
          _n(layer.sourceDuration + layer.speed / fps),
          '-i',
          _path(layer),
        ]);
        chain = [
          '[$input:v]${_retime(layer.speed)}',
          'fps=$fps',
          'tpad=stop=-1:stop_mode=clone',
          timing,
          'format=gbrap',
          ...look,
          ...size,
          ?alpha,
          ...moving,
          ?rotate,
        ];
      case FileSource() || GeneratedSource():
        final input = addInput(['-i', _path(layer)]);
        // A still image that neither resizes nor turns is drawn once.
        final stillRotate = rotate != null && rotation.isConstant && sizeStill;
        chain = [
          '[$input:v]format=gbrap',
          ...look,
          ...size,
          if (!scripted) ?alpha,
          if (stillRotate) rotate,
          'loop=loop=-1:size=1',
          timing,
          if (scripted) ?alpha,
          ...moving,
          if (!stillRotate) ?rotate,
        ];
    }
    graph.add('${chain.join(',')}[l$j]');

    final x = 'floor(${centerX.expression('t')}-w/2+0.5)';
    final y = 'floor(${centerY.expression('t')}-h/2+0.5)';
    graph.add(
      "[$below][l$j]overlay=x='$x':y='$y':eof_action=pass:format=gbrp:"
      "enable='between(t,${_n((a - 0.5) / fps)},${_n((b - 0.5) / fps)})'"
      '[v$j]',
    );
    return 'v$j';
  }

  String _path(PlanLayer layer) => switch (layer.source) {
    FileSource(:final path) => path,
    GeneratedSource() =>
      generatedPaths[layer.id] ??
          (throw StateError(
            'Generated layer ${layer.id} has not been written.',
          )),
    ColorSource() => throw StateError('Colour layer ${layer.id} has no file.'),
  };

  /// A `sendcmd` script driving `colorchannelmixer@l<j>`'s alpha gain along
  /// [opacity] (timeline seconds): one interpolating interval per segment,
  /// then the last value.
  String _opacityScript(int j, String id, _Pwl opacity) {
    final target = 'colorchannelmixer@l$j aa';
    final lines = ['# opacity of layer $id'];
    final points = opacity.points;
    for (var k = 0; k + 1 < points.length; k++) {
      final (t0, v0) = points[k];
      final (t1, v1) = points[k + 1];
      final interval = '${_n(t0)}-${_n(t1)}';
      lines.add(
        (v1 - v0).abs() < 1e-9
            ? '$interval [enter] $target ${_n(v0)};'
            : "$interval [expr] $target '${_n(v0)}${_signed(v1 - v0)}*TI';",
      );
    }
    final (tEnd, vEnd) = points.last;
    lines.add('${_n(tEnd)} [enter] $target ${_n(vEnd)};');
    return '${lines.join('\n')}\n';
  }

  // ---------------------------------------------------------------- audio --

  void _audio() {
    const rate = FfmpegTimelineRenderer.sampleRate;
    final total = (plan.duration * rate).round();
    final lanes = <int, List<(int, int, String)>>{};
    for (final (n, segment) in plan.audio.indexed) {
      if (!hasAudio(segment.path)) continue;
      final from = (segment.start * rate).round();
      final to = math.min(total, (segment.end * rate).round());
      final length = to - from;
      if (length <= 0) continue;
      final input = addInput([
        if (segment.sourceStart > 0) ...['-ss', _n(segment.sourceStart)],
        '-t',
        _n(segment.sourceDuration),
        '-i',
        segment.path,
      ]);
      final seconds = length / rate;
      final fadeIn = math.min(segment.fadeIn, seconds);
      final fadeOut = math.min(segment.fadeOut, seconds);
      final chain = [
        '[$input:a]aformat=sample_fmts=fltp:sample_rates=$rate:'
            'channel_layouts=stereo',
        'asetpts=PTS-STARTPTS',
        ..._atempo(segment.speed),
        'apad=whole_len=$length',
        'atrim=end_sample=$length',
        'asetpts=N/SR/TB',
        if ((segment.volume - 1).abs() > 1e-9) 'volume=${_n(segment.volume)}',
        if (fadeIn > 0) 'afade=t=in:st=0:d=${_n(fadeIn)}',
        if (fadeOut > 0)
          'afade=t=out:st=${_n(seconds - fadeOut)}:d=${_n(fadeOut)}',
      ];
      graph.add('${chain.join(',')}[s$n]');
      (lanes[segment.lane] ??= []).add((from, to, 's$n'));
    }

    final base = 'anullsrc=r=$rate:cl=stereo,atrim=end_sample=$total';
    if (lanes.isEmpty) {
      graph.add('$base[aout]');
      return;
    }
    final laneLabels = <String>[];
    for (final lane in lanes.keys.toList()..sort()) {
      final segments = lanes[lane]!..sort((x, y) => x.$1.compareTo(y.$1));
      var end = 0;
      final parts = <String>[];
      for (final (from, to, label) in segments) {
        final gap = math.max(0, from - end);
        if (gap > 0) {
          graph.add('[$label]adelay=delays=${gap}S:all=1[${label}d]');
          parts.add('${label}d');
        } else {
          parts.add(label);
        }
        end = math.max(end, from) + (to - from);
      }
      if (parts.length == 1) {
        laneLabels.add(parts.single);
      } else {
        graph.add(
          '${parts.map((l) => '[$l]').join()}'
          'concat=n=${parts.length}:v=0:a=1[lane$lane]',
        );
        laneLabels.add('lane$lane');
      }
    }
    graph
      ..add('$base[abase]')
      ..add(
        '[abase]${laneLabels.map((l) => '[$l]').join()}'
        'amix=inputs=${laneLabels.length + 1}:duration=first:'
        'dropout_transition=0:normalize=0,'
        'alimiter=limit=0.95:level=0[aout]',
      );
  }

  /// `atempo` factors, each within 0.5…2 (the range every ffmpeg accepts),
  /// whose product is [speed]; pitch is preserved.
  static List<String> _atempo(double speed) {
    final out = <String>[];
    var rest = speed;
    while (rest > 2 + 1e-9) {
      out.add('atempo=2');
      rest /= 2;
    }
    while (rest < 0.5 - 1e-9) {
      out.add('atempo=0.5');
      rest /= 0.5;
    }
    if ((rest - 1).abs() > 1e-9) out.add('atempo=${_n(rest)}');
    return out;
  }

  // -------------------------------------------------------------- helpers --

  static String _retime(double speed) => (speed - 1).abs() < 1e-9
      ? 'setpts=PTS-STARTPTS'
      : 'setpts=(PTS-STARTPTS)/${_n(speed)}';

  /// The unsharp mask `in + amount·(in − blur(in))`; ffmpeg's blur is a box,
  /// sized (odd, 3…23) so its standard deviation matches `sharpenSigma`.
  static String? _sharpen(PlanFilters filters) {
    if (filters.sharpen <= 0) return null;
    final sigma = filters.sharpenSigma > 0 ? filters.sharpenSigma : 2.0;
    var size = math.sqrt(12 * sigma * sigma + 1).round();
    if (size.isEven) size += 1;
    size = size.clamp(3, 23);
    final amount = _n(filters.sharpen.clamp(0.0, 5.0));
    return 'unsharp=$size:$size:$amount:$size:$size:$amount';
  }

  /// Gaussian luma noise (std = strength/√3 levels) whose RGB standard
  /// deviation is `grain`: in full-range YUV a luma step moves R, G, and B
  /// alike, so the grain is monochrome; `t` gives a new pattern every frame.
  static String? _grain(PlanFilters filters) {
    if (filters.grain <= 0) return null;
    final strength = (filters.grain * 255 * math.sqrt(3)).round().clamp(1, 100);
    return 'noise=c0s=$strength:c0f=t';
  }

  /// [filters] run in full-range BT.709 YUV, between RGB conversions.
  static String _yuv(String filters, {required bool alpha}) {
    final yuv = alpha ? 'yuva444p' : 'yuv444p';
    final rgb = alpha ? 'gbrap' : 'gbrp';
    return 'scale=out_color_matrix=bt709:out_range=pc,format=$yuv,$filters,'
        'scale=in_color_matrix=bt709:in_range=pc,format=$rgb';
  }

  static String _signed(double v) => v < 0 ? '-${_n(-v)}' : '+${_n(v)}';
}

/// [v] with at most six decimals and no trailing zeros.
String _n(double v) {
  var s = v.toStringAsFixed(6);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s == '-0' ? '0' : s;
}

/// A piecewise-linear function through sorted `(time, value)` points,
/// constant outside them, with collinear points dropped. [expression] renders
/// it for ffmpeg as a balanced `if(lt(…))` tree of clamped segments: its
/// length grows with the number of keys (never with frames), and each frame
/// evaluates only about `log₂(keys)` comparisons.
class _Pwl {
  _Pwl(List<(double, double)> raw) : points = _simplify(raw);

  final List<(double, double)> points;

  bool get isConstant => points.length == 1;

  double get first => points.first.$2;

  static List<(double, double)> _simplify(List<(double, double)> raw) {
    final out = <(double, double)>[];
    for (final point in raw) {
      if (out.isNotEmpty && point.$1 - out.last.$1 <= 1e-9) {
        out[out.length - 1] = point;
        continue;
      }
      while (out.length >= 2) {
        final (t0, v0) = out[out.length - 2];
        final (t1, v1) = out.last;
        final f = (t1 - t0) / (point.$1 - t0);
        if ((v0 + (point.$2 - v0) * f - v1).abs() > 1e-6) break;
        out.removeLast();
      }
      out.add(point);
    }
    if (out.length == 2 && (out[0].$2 - out[1].$2).abs() <= 1e-6) {
      out.removeLast();
    }
    return out;
  }

  String expression(String x) {
    if (isConstant) return _n(first);
    String segment(int i) {
      final (t0, v0) = points[i];
      final (t1, v1) = points[i + 1];
      if ((v1 - v0).abs() <= 1e-9) return _n(v0);
      final slope = (v1 - v0) / (t1 - t0);
      final ramp = t0 == 0
          ? 'clip($x,0,${_n(t1)})'
          : '(clip($x,${_n(t0)},${_n(t1)})-${_n(t0)})';
      final sign = slope < 0 ? '-' : '+';
      final head = v0 == 0 ? (slope < 0 ? '-' : '') : '${_n(v0)}$sign';
      return '$head${_n(slope.abs())}*$ramp';
    }

    String tree(int from, int to) {
      if (to == from + 1) return segment(from);
      final mid = (from + to) ~/ 2;
      return 'if(lt($x,${_n(points[mid].$1)}),'
          '${tree(from, mid)},${tree(mid, to)})';
    }

    return tree(0, points.length - 1);
  }
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
