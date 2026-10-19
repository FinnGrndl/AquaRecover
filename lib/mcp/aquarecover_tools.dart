import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../core/app_version.dart';
import '../core/media/media_classifier.dart';
import '../core/models/export_options.dart';
import '../core/models/image_transform_settings.dart';
import '../core/models/lut_profile.dart';
import '../core/models/media_kind.dart';
import '../core/models/restoration_settings.dart';
import '../core/models/video_edit_settings.dart';
import '../core/persistence/sidecar_service.dart';
import '../core/processing/lut_service.dart';
import '../core/processing/scene_analyzer.dart';
import '../core/processing/still_render_pipeline.dart';
import '../core/processing/underwater_processor.dart';
import 'media_host.dart';
import 'mcp_server.dart';

/// Builds the AquaRecover MCP server: underwater colour restoration for
/// photos and videos on the local machine, driven by Claude.
McpServer buildAquaRecoverMcpServer({
  PathPolicy? policy,
  HostTools? hostTools,
  void Function(String message)? log,
}) {
  final tools = AquaRecoverTools(
    policy: policy ?? PathPolicy(const []),
    decoder: MediaDecoder(hostTools ?? HostTools()),
  );
  return McpServer(
    name: 'aquarecover',
    version: aquaRecoverVersion,
    instructions: aquaRecoverInstructions,
    tools: tools.all,
    prompts: aquaRecoverPrompts,
    log: log,
  );
}

const aquaRecoverInstructions = '''
AquaRecover restores colour in underwater photos and videos on this computer.
Nothing is uploaded; files are read and written locally.

Recommended workflow:
1. analyze_media on a file to get its water type and a suggested preset.
2. preview_restoration to look at the result (use layout "side_by_side" to
   compare). Adjust with a preset, preset_strength and individual
   adjustments, then preview again until it looks right.
3. restore_image (or restore_video) to write the full-resolution result.
   batch_restore applies one look, or per-file suggestions, to many files.

Adjustments are absolute values on top of the chosen preset. Typical edits:
exposure (-1..1), shadows/highlights (-1..1), redRecovery (0..2.5),
saturation (0..3), contrast (0.1..3), hue (-1..1, keep within ±0.05),
vignette (0..1). describe_settings lists every parameter.
Outputs never overwrite existing files unless overwrite is true.
''';

final aquaRecoverPrompts = <McpPrompt>[
  McpPrompt(
    name: 'restore_dive_folder',
    description:
        'Analyse every photo in a folder, pick a look per scene and export '
        'restored copies.',
    arguments: const [
      {
        'name': 'folder',
        'description': 'Folder with dive photos',
        'required': true,
      },
      {
        'name': 'style',
        'description': 'Desired look, e.g. natural, vivid, documentary',
        'required': false,
      },
    ],
    render: (args) =>
        'Restore the underwater photos in ${args['folder'] ?? 'the folder'}. '
        'Start with analyze_media on a few representative files, preview one '
        'per water type side by side, tune towards a '
        '${args['style'] ?? 'natural'} look, then run batch_restore with '
        'auto_preset enabled and the adjustments you settled on. Report which '
        'presets were used and anything that needed manual attention.',
  ),
  McpPrompt(
    name: 'match_look',
    description: 'Tune a reference shot and apply the same look to others.',
    arguments: const [
      {
        'name': 'reference',
        'description': 'Photo to tune first',
        'required': true,
      },
      {
        'name': 'others',
        'description': 'Comma-separated photos that should match',
        'required': true,
      },
    ],
    render: (args) =>
        'Tune ${args['reference']} with preview_restoration until the colours '
        'look natural, then apply the exact same preset and adjustments to '
        '${args['others']} with batch_restore (auto_preset false) and preview '
        'one of them to confirm the match.',
  ),
];

class AquaRecoverTools {
  AquaRecoverTools({required this.policy, required this.decoder});

  final PathPolicy policy;
  final MediaDecoder decoder;
  final StillRenderPipeline pipeline = const StillRenderPipeline();
  final SceneAnalyzer analyzer = const SceneAnalyzer();

  static const _maxPreviewDimension = 2048;
  static const _maxBatchFiles = 500;

  List<McpTool> get all => [
    McpTool(
      name: 'analyze_media',
      title: 'Analyse underwater media',
      description:
          'Measures colour cast, red loss, brightness and clipping of a photo '
          '(or a video frame) and suggests a preset with a reason. Use it '
          'before editing.',
      readOnly: true,
      inputSchema: _object(
        {
          'path': _pathProperty('Photo or video to analyse.'),
          'time_seconds': {
            'type': 'number',
            'minimum': 0,
            'description': 'Video only: frame position (default: 10 % in).',
          },
        },
        required: ['path'],
      ),
      handler: _analyze,
    ),
    McpTool(
      name: 'describe_settings',
      title: 'List presets and parameters',
      description:
          'Lists restoration presets with their values, built-in LUT looks and '
          'every adjustable parameter with its range.',
      readOnly: true,
      inputSchema: _object(const {}),
      handler: (_, _) async => McpToolResult.json(_describeSettings()),
    ),
    McpTool(
      name: 'preview_restoration',
      title: 'Preview a restoration',
      description:
          'Renders a downscaled preview of a photo or video frame with the '
          'given look and returns it as an image so the result can be judged '
          'visually. Nothing is written to disk.',
      readOnly: true,
      inputSchema: _object(
        {
          'path': _pathProperty('Photo or video to preview.'),
          ..._lookProperties,
          'time_seconds': {
            'type': 'number',
            'minimum': 0,
            'description': 'Video only: frame position in seconds.',
          },
          'layout': {
            'type': 'string',
            'enum': ['after', 'side_by_side', 'before'],
            'default': 'after',
            'description': 'side_by_side puts the original on the left.',
          },
          'max_dimension': {
            'type': 'integer',
            'minimum': 256,
            'maximum': _maxPreviewDimension,
            'default': 1024,
          },
        },
        required: ['path'],
      ),
      handler: _preview,
    ),
    McpTool(
      name: 'restore_image',
      title: 'Restore a photo',
      description:
          'Writes a full-resolution restored copy of a photo plus an '
          'AquaRecover .aquarecover.json sidecar with the settings.',
      inputSchema: _object(
        {
          'path': _pathProperty('Photo to restore.'),
          'output_path': _pathProperty(
            'Destination file (default: next to the input, '
            '"<name> AquaRecover.jpg").',
          ),
          ..._lookProperties,
          ..._outputProperties,
        },
        required: ['path'],
      ),
      handler: _restoreImage,
    ),
    McpTool(
      name: 'batch_restore',
      title: 'Restore many photos',
      description:
          'Restores several photos (explicit paths or every supported photo in '
          'a folder) into an output folder. With auto_preset each photo gets '
          'its own suggested preset; adjustments apply on top.',
      inputSchema: _object({
        'paths': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'Photos to restore.',
        },
        'directory': _pathProperty(
          'Folder whose photos (not sub-folders) are restored.',
        ),
        'output_directory': _pathProperty(
          'Destination folder (default: "AquaRecover" inside the source '
          'folder).',
        ),
        'auto_preset': {
          'type': 'boolean',
          'default': false,
          'description': 'Use analyze_media suggestions per photo.',
        },
        ..._lookProperties,
        ..._outputProperties,
      }),
      handler: _batch,
    ),
    McpTool(
      name: 'restore_video',
      title: 'Restore a video',
      description:
          'Exports a restored H.264 video with ffmpeg (needs ffmpeg on PATH). '
          'Audio is kept unless keep_audio is false.',
      inputSchema: _object(
        {
          'path': _pathProperty('Video to restore.'),
          'output_path': _pathProperty(
            'Destination .mp4 or .mov (default: next to the input).',
          ),
          ..._lookProperties,
          'trim_start': {'type': 'number', 'minimum': 0},
          'trim_end': {'type': 'number', 'minimum': 0},
          'keep_audio': {'type': 'boolean', 'default': true},
          'overwrite': {'type': 'boolean', 'default': false},
        },
        required: ['path'],
      ),
      handler: _restoreVideo,
    ),
    McpTool(
      name: 'read_sidecar',
      title: 'Read AquaRecover edits',
      description:
          'Reads the settings stored in an .aquarecover.json sidecar (written '
          'by the app or by this server) so the same look can be reapplied.',
      readOnly: true,
      inputSchema: _object(
        {
          'path': _pathProperty(
            'The sidecar, or the exported file next to which it lives.',
          ),
        },
        required: ['path'],
      ),
      handler: _readSidecar,
    ),
  ];

  // ---------------------------------------------------------------- handlers

  Future<McpToolResult> _analyze(
    Map<String, Object?> args,
    McpCallContext context,
  ) async {
    final path = policy.check(_requireString(args, 'path'));
    final kind = decoder.kindOf(path);
    final frame = await _loadFrame(path, kind, args);
    final analysis = analyzer.analyze(frame.image);
    return McpToolResult.json({
      'file': p.basename(path),
      'kind': kind.name,
      'fileSizeBytes': await File(path).length(),
      if (frame.seconds != null) 'frameSeconds': frame.seconds,
      if (frame.durationSeconds != null)
        'durationSeconds': frame.durationSeconds,
      ...analysis.toJson(),
      'suggestedSettings': analysis.suggestedSettings.toJson(),
    });
  }

  Future<McpToolResult> _preview(
    Map<String, Object?> args,
    McpCallContext context,
  ) async {
    final path = policy.check(_requireString(args, 'path'));
    final kind = decoder.kindOf(path);
    final look = await _resolveLook(args);
    final maxDimension = _int(
      args,
      'max_dimension',
      1024,
    ).clamp(256, _maxPreviewDimension);
    final layout = args['layout'] as String? ?? 'after';
    final frame = await _loadFrame(path, kind, args);
    final before = StillRenderPipeline.downscale(frame.image, maxDimension);
    final after = layout == 'before'
        ? before
        : await pipeline.render(
            before,
            settings: look.settings,
            lutProfile: look.lut,
            transform: look.transform,
            quality: RestorationRenderQuality.preview,
          );
    final image = layout == 'side_by_side'
        ? _sideBySide(before, after, maxDimension)
        : after;
    final jpeg = StillRenderPipeline.encode(image, jpegQuality: 85);
    return McpToolResult.json(
      {
        'file': p.basename(path),
        'layout': layout,
        'previewSize': [image.width, image.height],
        if (frame.seconds != null) 'frameSeconds': frame.seconds,
        ...look.describe(),
      },
      extra: [McpImage(base64Encode(jpeg))],
    );
  }

  Future<McpToolResult> _restoreImage(
    Map<String, Object?> args,
    McpCallContext context,
  ) async {
    final path = policy.check(_requireString(args, 'path'));
    final kind = decoder.kindOf(path);
    if (!kind.isImage) {
      throw const McpToolError(
        'restore_image needs a photo; use restore_video.',
      );
    }
    final look = await _resolveLook(args);
    final options = _outputOptions(args);
    final output = policy.check(
      args['output_path'] as String? ??
          _defaultOutput(path, options.extension, p.dirname(path)),
    );
    final written = await _renderStill(path, output, look, options);
    return McpToolResult.json({
      'output': written.output,
      'sidecar': written.sidecar,
      'size': [written.width, written.height],
      ...look.describe(),
    });
  }

  Future<McpToolResult> _batch(
    Map<String, Object?> args,
    McpCallContext context,
  ) async {
    final inputs = <String>[];
    final explicit = args['paths'];
    if (explicit is List) {
      inputs.addAll(explicit.whereType<String>().map(policy.check));
    }
    final directory = args['directory'] as String?;
    if (directory != null) {
      final dir = Directory(policy.check(directory));
      if (!await dir.exists()) {
        throw McpToolError('Folder not found: $directory');
      }
      final files = await dir
          .list()
          .where((entity) => entity is File)
          .map((entity) => entity.path)
          .where(_isStill)
          // Skip earlier AquaRecover exports, which carry a sidecar.
          .where((path) => !File('$path.aquarecover.json').existsSync())
          .toList();
      files.sort();
      inputs.addAll(files);
    }
    if (inputs.isEmpty) {
      throw const McpToolError('Provide paths or a directory with photos.');
    }
    if (inputs.length > _maxBatchFiles) {
      throw McpToolError('At most $_maxBatchFiles files per batch.');
    }
    final options = _outputOptions(args);
    final outputDirectory = policy.check(
      args['output_directory'] as String? ??
          p.join(p.dirname(inputs.first), 'AquaRecover'),
    );
    await Directory(outputDirectory).create(recursive: true);
    final autoPreset = args['auto_preset'] == true;
    final baseLook = await _resolveLook(args);
    final results = <Map<String, Object?>>[];
    var failures = 0;
    for (var index = 0; index < inputs.length; index++) {
      final input = inputs[index];
      context.progress(
        index,
        total: inputs.length,
        message: 'Restoring ${p.basename(input)}',
      );
      try {
        if (!_isStill(input)) {
          throw const FormatException('Not a supported photo.');
        }
        var look = baseLook;
        if (autoPreset) {
          final analysis = analyzer.analyze(await decoder.decodeStill(input));
          look = await _resolveLook({
            ...args,
            'preset': analysis.suggestedPreset.name,
            'preset_strength': analysis.suggestedStrength,
          });
        }
        final output = _defaultOutput(
          input,
          options.extension,
          outputDirectory,
        );
        final written = await _renderStill(input, output, look, options);
        results.add({
          'input': p.basename(input),
          'output': written.output,
          'preset': look.settings.preset.name,
        });
      } on Object catch (error) {
        failures++;
        results.add({'input': p.basename(input), 'error': '$error'});
      }
    }
    context.progress(inputs.length, total: inputs.length, message: 'Done');
    return McpToolResult.json({
      'outputDirectory': outputDirectory,
      'restored': inputs.length - failures,
      'failed': failures,
      'results': results,
    });
  }

  Future<McpToolResult> _restoreVideo(
    Map<String, Object?> args,
    McpCallContext context,
  ) async {
    final path = policy.check(_requireString(args, 'path'));
    if (!decoder.kindOf(path).isVideo ||
        MediaClassifier.rawVideoExtensions.contains(
          MediaClassifier.extensionOf(path),
        )) {
      throw const McpToolError(
        'restore_video needs a standard video file (mp4, mov, mkv, ...).',
      );
    }
    final ffmpeg = decoder.requireFfmpeg();
    final look = await _resolveLook(args);
    final requested = args['output_path'] as String?;
    final output = policy.check(
      requested ?? _defaultOutput(path, 'mp4', p.dirname(path)),
    );
    final extension = p.extension(output).toLowerCase();
    if (extension != '.mp4' && extension != '.mov') {
      throw const McpToolError('Video output must end in .mp4 or .mov.');
    }
    _ensureWritable(output, args['overwrite'] == true);
    final start = (args['trim_start'] as num?)?.toDouble();
    final end = (args['trim_end'] as num?)?.toDouble();
    final trim = VideoEditSettings(
      enabled: start != null || end != null,
      startSeconds: start ?? 0,
      endSeconds: end,
    );
    try {
      trim.validate();
    } on FormatException catch (error) {
      throw McpToolError(error.message);
    }
    final keepAudio = args['keep_audio'] != false;
    final filters = look.settings
        .ffmpegFilters(extraFilters: LutService.videoFiltersFor(look.lut))
        .join(',');
    final ffmpegArgs = <String>[
      '-hide_banner',
      '-nostdin',
      '-loglevel',
      'error',
      '-y',
      ...trim.toFfmpegInputPrefixArgs(),
      '-i',
      path,
      '-map',
      '0:v:0',
      if (keepAudio) ...['-map', '0:a?'],
      '-map_metadata',
      '-1',
      '-vf',
      filters,
      '-c:v',
      'libx264',
      '-preset',
      'medium',
      '-crf',
      '18',
      '-pix_fmt',
      'yuv420p',
      if (keepAudio) ...['-c:a', 'aac', '-b:a', '192k'] else '-an',
      ...trim.toFfmpegOutputArgs(),
      '-movflags',
      '+faststart',
      output,
    ];
    context.progress(0, message: 'Encoding ${p.basename(path)}');
    final result = await Process.run(ffmpeg, ffmpegArgs);
    if (result.exitCode != 0) {
      throw McpToolError(
        'ffmpeg failed (exit ${result.exitCode}): '
        '${(result.stderr as String).trim()}',
      );
    }
    final sidecar = await const SidecarService().write(
      inputPath: path,
      outputPath: output,
      settings: look.settings,
      exportOptions: ExportOptions(
        videoFormat: extension == '.mov'
            ? VideoOutputFormat.mov
            : VideoOutputFormat.mp4,
        keepAudio: keepAudio,
      ),
      lutProfile: look.lut,
      trim: trim,
    );
    return McpToolResult.json({
      'output': output,
      'sidecar': sidecar,
      ...look.describe(),
    });
  }

  Future<McpToolResult> _readSidecar(
    Map<String, Object?> args,
    McpCallContext context,
  ) async {
    var path = policy.check(_requireString(args, 'path'));
    if (!path.endsWith('.aquarecover.json')) path = '$path.aquarecover.json';
    final file = File(path);
    if (!await file.exists()) {
      throw McpToolError('No AquaRecover sidecar found at $path.');
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map ||
        decoded['schema'] != 'com.aquarecover.edit-sidecar.v1') {
      throw const McpToolError('Not an AquaRecover edit sidecar.');
    }
    final map = decoded.cast<String, Object?>();
    final settings = RestorationSettings.fromJson(
      (map['settings'] as Map? ?? const {}).cast<String, Object?>(),
    );
    final lut = LutProfile.fromJson(
      (map['lut'] as Map? ?? const {}).cast<String, Object?>(),
    );
    return McpToolResult.json({
      'sidecar': path,
      'inputName': map['inputName'],
      'outputName': map['outputName'],
      'createdAt': map['createdAt'],
      'preset': settings.preset.name,
      'preset_strength': settings.presetStrength,
      'adjustments': settings.toJson()
        ..remove('preset')
        ..remove('presetStrength'),
      if (lut.isEnabled) 'lut': lut.kind.name,
      if (lut.isEnabled) 'lut_intensity': lut.intensity,
      if (lut.isCustomCube) 'cube_path': lut.path,
      'transform': map['transform'],
    });
  }

  // ----------------------------------------------------------------- helpers

  Future<_WrittenStill> _renderStill(
    String input,
    String output,
    _Look look,
    _OutputOptions options,
  ) async {
    _ensureWritable(output, options.overwrite);
    final source = await decoder.decodeStill(input);
    final rendered = await pipeline.render(
      source,
      settings: look.settings,
      lutProfile: look.lut,
      transform: look.transform,
    );
    final bytes = StillRenderPipeline.encode(
      rendered,
      png: options.png,
      jpegQuality: options.jpegQuality,
    );
    await File(output).parent.create(recursive: true);
    await File(output).writeAsBytes(bytes, flush: true);
    final sidecar = options.writeSidecar
        ? await const SidecarService().write(
            inputPath: input,
            outputPath: output,
            settings: look.settings.copyWith(jpegQuality: options.jpegQuality),
            exportOptions: ExportOptions(
              imageFormat: options.png
                  ? ImageOutputFormat.png
                  : ImageOutputFormat.jpeg,
            ),
            lutProfile: look.lut,
            trim: const VideoEditSettings(),
            transform: look.transform,
          )
        : null;
    return _WrittenStill(output, sidecar, rendered.width, rendered.height);
  }

  Future<_Frame> _loadFrame(
    String path,
    MediaKind kind,
    Map<String, Object?> args,
  ) async {
    if (kind.isImage) return _Frame(await decoder.decodeStill(path));
    if (MediaClassifier.rawVideoExtensions.contains(
      MediaClassifier.extensionOf(path),
    )) {
      throw const McpToolError(
        'Raw video streams need a format description; use the app.',
      );
    }
    final duration = await decoder.videoDuration(path);
    final requested = (args['time_seconds'] as num?)?.toDouble();
    final seconds = requested ?? (duration == null ? 0.0 : duration * .1);
    return _Frame(
      await decoder.decodeVideoFrame(path, seconds),
      seconds: seconds,
      durationSeconds: duration,
    );
  }

  Future<_Look> _resolveLook(Map<String, Object?> args) async {
    final presetName = args['preset'] as String? ?? 'auto';
    final preset = RestorationPreset.values.firstWhere(
      (value) => value.name == presetName,
      orElse: () => throw McpToolError(
        'Unknown preset "$presetName". Use one of '
        '${RestorationPreset.values.map((value) => value.name).join(', ')}.',
      ),
    );
    final strength = ((args['preset_strength'] as num?)?.toDouble() ?? 1)
        .clamp(0.0, 1.0)
        .toDouble();
    var settings = preset.settingsAtStrength(strength);
    final adjustments = args['adjustments'];
    if (adjustments is Map) {
      final unknown = adjustments.keys
          .where((key) => !_parameterRanges.containsKey(key))
          .toList();
      if (unknown.isNotEmpty) {
        throw McpToolError(
          'Unknown adjustment(s) ${unknown.join(', ')}. Valid: '
          '${_parameterRanges.keys.join(', ')}.',
        );
      }
      final merged = settings.toJson();
      for (final entry in adjustments.entries) {
        final value = entry.value;
        if (value is! num || !value.isFinite) {
          throw McpToolError('Adjustment ${entry.key} must be a number.');
        }
        final range = _parameterRanges[entry.key]!;
        merged[entry.key as String] = value.toDouble().clamp(
          range.$1,
          range.$2,
        );
      }
      settings = RestorationSettings.fromJson(merged);
    }

    var lut = LutProfile.none;
    final cubePath = args['cube_path'] as String?;
    final lutName = args['lut'] as String?;
    final lutIntensity = ((args['lut_intensity'] as num?)?.toDouble() ?? 1)
        .clamp(0.0, 1.0)
        .toDouble();
    if (cubePath != null) {
      final checked = policy.check(cubePath);
      await CubeLut.read(checked);
      lut = LutProfile.customCube(
        checked,
        name: p.basename(checked),
        intensity: lutIntensity,
      );
    } else if (lutName != null && lutName != 'none') {
      final builtIn = LutProfile.builtIns.where(
        (profile) => profile.kind.name == lutName,
      );
      if (builtIn.isEmpty) {
        throw McpToolError(
          'Unknown LUT "$lutName". Use coralWarm, blueWater or greenWater.',
        );
      }
      lut = builtIn.first.copyWith(intensity: lutIntensity);
    }

    var transform = const ImageTransformSettings();
    final rawTransform = args['transform'];
    if (rawTransform is Map) {
      transform = ImageTransformSettings.fromJson({
        ...transform.toJson(),
        ...rawTransform.cast<String, Object?>(),
      });
    }
    return _Look(settings, lut, transform);
  }

  _OutputOptions _outputOptions(Map<String, Object?> args) {
    final format = args['format'] as String? ?? 'jpeg';
    if (format != 'jpeg' && format != 'png') {
      throw const McpToolError('format must be "jpeg" or "png".');
    }
    return _OutputOptions(
      png: format == 'png',
      jpegQuality: _int(args, 'jpeg_quality', 94).clamp(1, 100),
      overwrite: args['overwrite'] == true,
      writeSidecar: args['write_sidecar'] != false,
    );
  }

  static String _defaultOutput(String input, String extension, String dir) {
    final stem = p.basenameWithoutExtension(input);
    return p.join(dir, '$stem AquaRecover.$extension');
  }

  static void _ensureWritable(String output, bool overwrite) {
    if (!overwrite && File(output).existsSync()) {
      throw McpToolError(
        '$output already exists. Pass overwrite: true or choose another '
        'output_path.',
      );
    }
  }

  static bool _isStill(String path) {
    final extension = MediaClassifier.extensionOf(path);
    return MediaClassifier.imageExtensions.contains(extension) ||
        MediaClassifier.rawPhotoExtensions.contains(extension);
  }

  static img.Image _sideBySide(img.Image before, img.Image after, int max) {
    const gap = 8;
    final canvas = img.Image(
      width: before.width + after.width + gap,
      height: math.max(before.height, after.height),
      numChannels: 3,
    );
    img.fill(canvas, color: img.ColorRgb8(18, 18, 18));
    img.compositeImage(canvas, before);
    img.compositeImage(canvas, after, dstX: before.width + gap);
    return StillRenderPipeline.downscale(canvas, max * 2);
  }

  static String _requireString(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value is! String || value.trim().isEmpty) {
      throw McpToolError('"$key" is required.');
    }
    return value;
  }

  static int _int(Map<String, Object?> args, String key, int fallback) {
    final value = args[key];
    return value is num ? value.toInt() : fallback;
  }

  static Map<String, Object?> _describeSettings() => {
    'presets': [
      for (final preset in RestorationPreset.values)
        {
          'name': preset.name,
          'label': preset.label,
          'description': preset.help,
          'settings': preset.settings.toJson(),
        },
    ],
    'luts': [
      for (final lut in LutProfile.builtIns.skip(1))
        {'name': lut.kind.name, 'label': lut.name},
    ],
    'parameters': {
      for (final entry in _parameterRanges.entries)
        entry.key: {
          'min': entry.value.$1,
          'max': entry.value.$2,
          'neutral': RestorationPreset.none.settings.toJson()[entry.key],
          'description': entry.value.$3,
        },
    },
    'transform': {
      'quarterTurns': 'Clockwise 90° turns (0-3).',
      'straightenDegrees': 'Fine rotation, -45..45.',
      'flipHorizontal': 'Mirror left/right.',
      'flipVertical': 'Mirror top/bottom.',
      'aspectRatio':
          'original, freeform, square, fourThree or sixteenNine crop.',
      'zoom': 'Crop zoom 1..20.',
      'offsetX': 'Crop position -1..1.',
      'offsetY': 'Crop position -1..1.',
    },
  };

  static const Map<String, (double, double, String)> _parameterRanges = {
    'recovery': (0, 1.5, 'Overall strength of the underwater correction.'),
    'redRecovery': (0, 2.5, 'How much missing red is rebuilt.'),
    'autoWhiteBalance': (0, 1, 'Pull towards neutral grey.'),
    'contrastStretch': (0, 1, 'Percentile-based tonal stretch.'),
    'contrast': (0.1, 3, 'Contrast multiplier (1 = unchanged).'),
    'gamma': (0.1, 3, 'Midtone gamma (1 = unchanged, <1 darker).'),
    'saturation': (0, 3, 'Colour saturation (1 = unchanged).'),
    'vibrance': (0, 1, 'Boosts muted colours more than saturated ones.'),
    'clarity': (0, 1.2, 'Local contrast on export.'),
    'sharpness': (0, 1.2, 'Export sharpening.'),
    'hazeReduction': (0, 1, 'Removes backscatter haze.'),
    'highlightProtection': (0, 1, 'Protects bright areas from the red lift.'),
    'hue': (-1, 1, 'Hue rotation; ±1 = ±180°. Use small values.'),
    'brightness': (-1, 1, 'Linear brightness offset.'),
    'exposure': (-1, 1, 'Exposure in stops.'),
    'highlights': (-1, 1, 'Lift or recover highlights.'),
    'shadows': (-1, 1, 'Lift or deepen shadows.'),
    'blackPoint': (0, 1, 'Raises the black point (deeper blacks).'),
    'vignette': (0, 1, 'Darkens the corners.'),
  };

  static Map<String, Object?> _pathProperty(String description) => {
    'type': 'string',
    'description': '$description Absolute paths or ~/ are supported.',
  };

  static final Map<String, Object?> _lookProperties = {
    'preset': {
      'type': 'string',
      'enum': [for (final preset in RestorationPreset.values) preset.name],
      'default': 'auto',
      'description': 'Starting look; see describe_settings.',
    },
    'preset_strength': {
      'type': 'number',
      'minimum': 0,
      'maximum': 1,
      'default': 1,
    },
    'adjustments': {
      'type': 'object',
      'description':
          'Absolute parameter values that replace the preset values, e.g. '
          '{"exposure": 0.15, "redRecovery": 1.6}. See describe_settings.',
      'additionalProperties': {'type': 'number'},
    },
    'lut': {
      'type': 'string',
      'enum': ['none', 'coralWarm', 'blueWater', 'greenWater'],
      'default': 'none',
    },
    'lut_intensity': {
      'type': 'number',
      'minimum': 0,
      'maximum': 1,
      'default': 1,
    },
    'cube_path': {
      'type': 'string',
      'description': 'Optional .cube 3D LUT applied after restoration.',
    },
    'transform': {
      'type': 'object',
      'description':
          'Optional crop/rotation, same fields as the app; see '
          'describe_settings.',
    },
  };

  static const Map<String, Object?> _outputProperties = {
    'format': {
      'type': 'string',
      'enum': ['jpeg', 'png'],
      'default': 'jpeg',
    },
    'jpeg_quality': {
      'type': 'integer',
      'minimum': 1,
      'maximum': 100,
      'default': 94,
    },
    'overwrite': {'type': 'boolean', 'default': false},
    'write_sidecar': {'type': 'boolean', 'default': true},
  };

  static Map<String, Object?> _object(
    Map<String, Object?> properties, {
    List<String> required = const [],
  }) => {
    'type': 'object',
    'properties': properties,
    if (required.isNotEmpty) 'required': required,
    'additionalProperties': false,
  };
}

class _Look {
  const _Look(this.settings, this.lut, this.transform);

  final RestorationSettings settings;
  final LutProfile lut;
  final ImageTransformSettings transform;

  Map<String, Object?> describe() => {
    'preset': settings.preset.name,
    'preset_strength': settings.presetStrength,
    'settings': settings.toJson(),
    if (lut.isEnabled) 'lut': {'name': lut.name, 'intensity': lut.intensity},
    if (!transform.isIdentity) 'transform': transform.toJson(),
  };
}

class _OutputOptions {
  const _OutputOptions({
    required this.png,
    required this.jpegQuality,
    required this.overwrite,
    required this.writeSidecar,
  });

  final bool png;
  final int jpegQuality;
  final bool overwrite;
  final bool writeSidecar;

  String get extension => png ? 'png' : 'jpg';
}

class _Frame {
  const _Frame(this.image, {this.seconds, this.durationSeconds});

  final img.Image image;
  final double? seconds;
  final double? durationSeconds;
}

class _WrittenStill {
  const _WrittenStill(this.output, this.sidecar, this.width, this.height);

  final String output;
  final String? sidecar;
  final int width;
  final int height;
}
