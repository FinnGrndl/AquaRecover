import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart' hide Uint8List;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/models/lut_profile.dart';
import '../../../core/models/restoration_settings.dart';
import '../../../core/processing/preview_render_worker.dart';

class RestoredImagePreview extends StatefulWidget {
  const RestoredImagePreview({
    super.key,
    required this.path,
    required this.settings,
    this.lutProfile = LutProfile.none,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.fallback,
    this.maxDimension = 1280,
  });

  final String path;
  final RestorationSettings settings;
  final LutProfile lutProfile;
  final BoxFit fit;
  final Alignment alignment;
  final Widget? fallback;
  final int maxDimension;

  @visibleForTesting
  static Future<Uint8List> renderPreviewBytesForTest({
    required String path,
    required RestorationSettings settings,
    LutProfile lutProfile = LutProfile.none,
    int maxDimension = 1280,
  }) {
    return renderPreviewBytes(
      PreviewRenderRequest(
        path: path,
        settings: settings.toJson(),
        lutProfile: lutProfile.toJson(),
        maxDimension: maxDimension,
      ),
    );
  }

  @override
  State<RestoredImagePreview> createState() => _RestoredImagePreviewState();
}

class _RestoredImagePreviewState extends State<RestoredImagePreview> {
  static const _nativeImageChannel = MethodChannel('aqua_recover/image');
  static final LinkedHashMap<String, Uint8List> _previewCache =
      LinkedHashMap<String, Uint8List>();
  static final Map<String, Future<Uint8List>> _inFlightPreviews = {};
  static const _maxCachedPreviews = 12;

  Timer? _debounce;
  Uint8List? _bytes;
  Object? _error;
  int _requestId = 0;
  bool _rendering = false;
  late String _cacheKey;

  @override
  void initState() {
    super.initState();
    _cacheKey = _cacheKeyFor(widget);
    _bytes = _previewCache[_cacheKey];
    if (_bytes == null) _scheduleRender(immediate: true);
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
      _cacheKey = _cacheKeyFor(widget);
      final cached = _previewCache[_cacheKey];
      if (cached != null) {
        _debounce?.cancel();
        _requestId++;
        _bytes = cached;
        _rendering = false;
        _error = null;
      } else {
        _scheduleRender();
      }
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
            alignment: widget.alignment,
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
      final request = PreviewRenderRequest(
        path: widget.path,
        settings: widget.settings.toJson(),
        lutProfile: widget.lutProfile.toJson(),
        maxDimension: widget.maxDimension,
      );
      final cacheKey = _cacheKey;
      var future = _inFlightPreviews[cacheKey];
      if (future == null) {
        future = _renderPreview(request);
        _inFlightPreviews[cacheKey] = future;
      }
      late Uint8List bytes;
      try {
        bytes = await future;
      } finally {
        if (identical(_inFlightPreviews[cacheKey], future)) {
          _inFlightPreviews.remove(cacheKey);
        }
      }
      if (!mounted || id != _requestId) return;
      _storeCachedPreview(cacheKey, bytes);
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

  static String _cacheKeyFor(RestoredImagePreview widget) {
    return jsonEncode({
      'path': widget.path,
      'settings': widget.settings.toJson(),
      'lut': widget.lutProfile.toJson(),
      'maxDimension': widget.maxDimension,
    });
  }

  static void _storeCachedPreview(String key, Uint8List bytes) {
    _previewCache.remove(key);
    _previewCache[key] = bytes;
    while (_previewCache.length > _maxCachedPreviews) {
      _previewCache.remove(_previewCache.keys.first);
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

  Future<Uint8List> _renderPreview(PreviewRenderRequest request) async {
    if (Platform.isIOS || Platform.isMacOS) {
      final nativeSettings = widget.settings.toJson();
      final nativeLut = widget.lutProfile.toJson();
      try {
        return await _renderNativePreview(
          request,
          settings: nativeSettings,
          lutProfile: nativeLut,
        );
      } on MissingPluginException {
        // Unit tests and development shells without the iOS runner use Dart.
      } on PlatformException {
        // Keep preview responsive even when a platform decoder rejects a file.
      }
    }
    return PreviewRenderWorker.shared.render(request);
  }

  Future<Uint8List> _renderNativePreview(
    PreviewRenderRequest request, {
    required Map<String, Object> settings,
    required Map<String, Object?> lutProfile,
  }) async {
    final outputPath = await _previewOutputPath(request.path);
    await Directory(p.dirname(outputPath)).create(recursive: true);
    final restored = await _nativeImageChannel.invokeMethod<String>(
      'restoreImage',
      {
        'inputPath': request.path,
        'outputPath': outputPath,
        'maxDimension': request.maxDimension,
        'settings': settings,
        'exportOptions': const {
          'imageFormat': 'jpeg',
          'stripMetadata': true,
          'saveToPhotoLibrary': false,
          'keepAudio': false,
        },
        'lutProfile': lutProfile,
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
