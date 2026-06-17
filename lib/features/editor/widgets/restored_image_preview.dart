import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' hide Uint8List;
import 'package:flutter/services.dart' hide Uint8List;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/models/lut_profile.dart';
import '../../../core/models/restoration_settings.dart';
import '../../../core/processing/lut_service.dart';
import '../../../core/processing/underwater_processor.dart';

class RestoredImagePreview extends StatefulWidget {
  const RestoredImagePreview({
    super.key,
    required this.path,
    required this.settings,
    this.lutProfile = LutProfile.none,
    this.fit = BoxFit.contain,
    this.fallback,
    this.maxDimension = 1280,
  });

  final String path;
  final RestorationSettings settings;
  final LutProfile lutProfile;
  final BoxFit fit;
  final Widget? fallback;
  final int maxDimension;

  @visibleForTesting
  static Future<Uint8List> renderPreviewBytesForTest({
    required String path,
    required RestorationSettings settings,
    LutProfile lutProfile = LutProfile.none,
    int maxDimension = 1280,
  }) {
    return _renderPreviewBytes(
      _PreviewRequest(
        path: path,
        settings: _settingsToMap(settings),
        lutProfile: _lutToMap(lutProfile),
        maxDimension: maxDimension,
      ),
    );
  }

  @override
  State<RestoredImagePreview> createState() => _RestoredImagePreviewState();
}

class _RestoredImagePreviewState extends State<RestoredImagePreview> {
  static const _nativeImageChannel = MethodChannel('aqua_recover/image');

  Timer? _debounce;
  Uint8List? _bytes;
  Object? _error;
  int _requestId = 0;
  bool _rendering = false;

  @override
  void initState() {
    super.initState();
    _scheduleRender(immediate: true);
  }

  @override
  void didUpdateWidget(covariant RestoredImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.settings != widget.settings ||
        oldWidget.lutProfile.kind != widget.lutProfile.kind ||
        oldWidget.lutProfile.path != widget.lutProfile.path ||
        oldWidget.lutProfile.intensity != widget.lutProfile.intensity ||
        oldWidget.maxDimension != widget.maxDimension) {
      _scheduleRender();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = _bytes == null
        ? widget.fallback ?? _previewPlaceholder(context)
        : Image.memory(
            _bytes!,
            fit: widget.fit,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) =>
                widget.fallback ?? _previewPlaceholder(context),
          );
    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        if (_rendering)
          Positioned(
            right: 10,
            bottom: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: CupertinoColors.black.withValues(alpha: .48),
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: CupertinoActivityIndicator(color: CupertinoColors.white),
              ),
            ),
          ),
      ],
    );
  }

  void _scheduleRender({bool immediate = false}) {
    _debounce?.cancel();
    final id = ++_requestId;
    Future<void> run() => _render(id);
    if (immediate || _bytes == null) {
      unawaited(run());
    } else {
      _debounce = Timer(const Duration(milliseconds: 180), () {
        unawaited(run());
      });
    }
  }

  Future<void> _render(int id) async {
    setState(() {
      _rendering = true;
      _error = null;
    });
    try {
      final request = _PreviewRequest(
        path: widget.path,
        settings: _settingsToMap(widget.settings),
        lutProfile: _lutToMap(widget.lutProfile),
        maxDimension: widget.maxDimension,
      );
      final bytes = await _renderPreview(request);
      if (!mounted || id != _requestId) return;
      setState(() {
        _bytes = bytes;
        _rendering = false;
      });
    } on Object catch (error) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _error = error;
        _rendering = false;
      });
    }
  }

  Widget _previewPlaceholder(BuildContext context) {
    final secondary = CupertinoColors.white.withValues(alpha: .72);
    return ColoredBox(
      color: CupertinoColors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _error == null
                  ? CupertinoIcons.wand_stars
                  : CupertinoIcons.exclamationmark_triangle,
              color: secondary,
              size: 34,
            ),
            const SizedBox(height: 8),
            Text(
              _error == null ? 'Rendering preview' : 'Preview unavailable',
              style: CupertinoTheme.of(
                context,
              ).textTheme.textStyle.copyWith(color: secondary),
            ),
          ],
        ),
      ),
    );
  }

  Future<Uint8List> _renderPreview(_PreviewRequest request) async {
    if (Platform.isIOS && !widget.lutProfile.isCustomCube) {
      try {
        return await _renderNativePreview(request);
      } on MissingPluginException {
        // Unit tests and development shells without the iOS runner use Dart.
      } on PlatformException {
        // Keep preview responsive even when a platform decoder rejects a file.
      }
    }
    return compute(_renderPreviewBytes, request);
  }

  Future<Uint8List> _renderNativePreview(_PreviewRequest request) async {
    final outputPath = await _previewOutputPath(request.path);
    await Directory(p.dirname(outputPath)).create(recursive: true);
    final restored = await _nativeImageChannel.invokeMethod<String>(
      'restoreImage',
      {
        'inputPath': request.path,
        'outputPath': outputPath,
        'maxDimension': request.maxDimension,
        'settings': widget.settings.toJson(),
        'exportOptions': const {
          'imageFormat': 'jpeg',
          'stripMetadata': true,
          'saveToPhotoLibrary': false,
          'keepAudio': false,
        },
        'lutProfile': widget.lutProfile.toJson(),
      },
    );
    if (restored == null || restored.isEmpty) {
      throw StateError('Native preview did not return an output path.');
    }
    try {
      return await File(restored).readAsBytes();
    } finally {
      unawaited(_deletePreviewFile(restored));
    }
  }

  Future<String> _previewOutputPath(String inputPath) async {
    final dir = await getTemporaryDirectory();
    final stem = p
        .basenameWithoutExtension(inputPath)
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    final safeStem = stem.isEmpty ? 'preview' : stem;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return p.join(dir.path, 'AquaRecover Previews', '${safeStem}_$stamp.jpg');
  }

  Future<void> _deletePreviewFile(String path) async {
    try {
      await File(path).delete();
    } on Object {
      // Temporary preview files are best-effort cleanup.
    }
  }
}

class _PreviewRequest {
  const _PreviewRequest({
    required this.path,
    required this.settings,
    required this.lutProfile,
    required this.maxDimension,
  });

  final String path;
  final Map<String, Object?> settings;
  final Map<String, Object?> lutProfile;
  final int maxDimension;
}

Future<Uint8List> _renderPreviewBytes(_PreviewRequest request) async {
  final file = File(request.path);
  if (!await file.exists()) {
    throw FileSystemException('Image not found.', request.path);
  }
  final decoded = img.decodeImage(await file.readAsBytes());
  if (decoded == null) {
    throw const FormatException('Could not decode image preview.');
  }
  final resized = _resizeForPreview(decoded, request.maxDimension);
  final restored = const UnderwaterProcessor().restoreImage(
    resized,
    _settingsFromMap(request.settings),
    quality: RestorationRenderQuality.preview,
  );
  final withLut = await const LutService().apply(
    restored,
    _lutFromMap(request.lutProfile),
  );
  return Uint8List.fromList(img.encodeJpg(withLut, quality: 92));
}

img.Image _resizeForPreview(img.Image source, int maxDimension) {
  final maxSide = math.max(source.width, source.height);
  if (maxSide <= maxDimension) return source;
  final scale = maxDimension / maxSide;
  return img.copyResize(
    source,
    width: math.max(1, (source.width * scale).round()),
    height: math.max(1, (source.height * scale).round()),
    interpolation: img.Interpolation.linear,
  );
}

Map<String, Object?> _settingsToMap(RestorationSettings s) => {
  'preset': s.preset.index,
  'recovery': s.recovery,
  'redRecovery': s.redRecovery,
  'autoWhiteBalance': s.autoWhiteBalance,
  'contrastStretch': s.contrastStretch,
  'contrast': s.contrast,
  'gamma': s.gamma,
  'saturation': s.saturation,
  'vibrance': s.vibrance,
  'clarity': s.clarity,
  'sharpness': s.sharpness,
  'hazeReduction': s.hazeReduction,
  'highlightProtection': s.highlightProtection,
  'hue': s.hue,
  'brightness': s.brightness,
  'exposure': s.exposure,
  'highlights': s.highlights,
  'shadows': s.shadows,
  'blackPoint': s.blackPoint,
  'vignette': s.vignette,
  'jpegQuality': s.jpegQuality,
};

RestorationSettings _settingsFromMap(Map<String, Object?> map) {
  double d(String key) => (map[key] as num).toDouble();
  return RestorationSettings(
    preset: RestorationPreset.values[(map['preset'] as num).toInt()],
    recovery: d('recovery'),
    redRecovery: d('redRecovery'),
    autoWhiteBalance: d('autoWhiteBalance'),
    contrastStretch: d('contrastStretch'),
    contrast: d('contrast'),
    gamma: d('gamma'),
    saturation: d('saturation'),
    vibrance: d('vibrance'),
    clarity: d('clarity'),
    sharpness: d('sharpness'),
    hazeReduction: d('hazeReduction'),
    highlightProtection: d('highlightProtection'),
    hue: d('hue'),
    brightness: d('brightness'),
    exposure: d('exposure'),
    highlights: d('highlights'),
    shadows: d('shadows'),
    blackPoint: d('blackPoint'),
    vignette: d('vignette'),
    jpegQuality: (map['jpegQuality'] as num).toInt(),
  );
}

Map<String, Object?> _lutToMap(LutProfile profile) => {
  'kind': profile.kind.index,
  'name': profile.name,
  'path': profile.path,
  'intensity': profile.intensity,
};

LutProfile _lutFromMap(Map<String, Object?> map) {
  return LutProfile(
    kind: LutKind.values[(map['kind'] as num).toInt()],
    name: map['name'] as String,
    path: map['path'] as String?,
    intensity: (map['intensity'] as num).toDouble(),
  );
}
