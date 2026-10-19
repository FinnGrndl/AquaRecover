import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/lut_profile.dart';
import '../models/restoration_settings.dart';
import 'lut_service.dart';
import 'underwater_processor.dart';

/// One preview render: the source file, the edit state, and the longest
/// output side. Settings and LUT travel as JSON maps so the request is cheap
/// to send to the worker isolate.
class PreviewRenderRequest {
  const PreviewRenderRequest({
    required this.path,
    required this.settings,
    required this.lutProfile,
    required this.maxDimension,
    this.jpegQuality = 92,
  });

  final String path;
  final Map<String, Object?> settings;
  final Map<String, Object?> lutProfile;
  final int maxDimension;
  final int jpegQuality;
}

/// Renders editor previews on one long-lived background isolate.
///
/// Decoding a full-resolution still dominates preview latency. The worker
/// keeps the last few decoded and downscaled sources, so moving a slider only
/// re-runs the restoration on the preview-sized bitmap. Requests are handled
/// one at a time; a request that is still queued when a newer one for the same
/// file arrives is folded into the newer one, so fast slider drags never build
/// up a backlog.
class PreviewRenderWorker {
  PreviewRenderWorker({this.cachedSources = 3});

  static final PreviewRenderWorker shared = PreviewRenderWorker();

  final int cachedSources;

  SendPort? _commands;
  Future<SendPort>? _starting;
  ReceivePort? _responses;
  int _nextId = 0;
  _QueuedRender? _active;
  final LinkedHashMap<String, _QueuedRender> _queue =
      LinkedHashMap<String, _QueuedRender>();
  final Map<int, _QueuedRender> _awaitingReply = {};

  Future<Uint8List> render(PreviewRenderRequest request) {
    final queued = _queue[request.path];
    if (queued != null) {
      queued.request = request;
      final completer = Completer<Uint8List>();
      queued.completers.add(completer);
      return completer.future;
    }
    final entry = _QueuedRender(request);
    _queue[request.path] = entry;
    _pump();
    return entry.completers.first.future;
  }

  Future<void> _pump() async {
    if (_active != null || _queue.isEmpty) return;
    final key = _queue.keys.first;
    final entry = _queue.remove(key)!;
    _active = entry;
    try {
      final commands = await _ensureStarted();
      final id = _nextId++;
      _awaitingReply[id] = entry;
      final request = entry.request;
      commands.send(<Object?>[
        id,
        request.path,
        request.settings,
        request.lutProfile,
        request.maxDimension,
        request.jpegQuality,
      ]);
    } on Object catch (error, stackTrace) {
      _active = null;
      entry.completeError(error, stackTrace);
      unawaited(_pump());
    }
  }

  Future<SendPort> _ensureStarted() {
    final commands = _commands;
    if (commands != null) return Future.value(commands);
    return _starting ??= _start();
  }

  Future<SendPort> _start() async {
    final responses = ReceivePort('AquaRecover preview responses');
    _responses = responses;
    final ready = Completer<SendPort>();
    responses.listen((message) {
      if (message is SendPort) {
        _commands = message;
        ready.complete(message);
        return;
      }
      final reply = message as List<Object?>;
      final entry = _awaitingReply.remove(reply[0]! as int);
      if (identical(entry, _active)) _active = null;
      if (entry != null) {
        final payload = reply[1];
        if (payload is TransferableTypedData) {
          entry.complete(payload.materialize().asUint8List());
        } else {
          entry.completeError(StateError(payload as String), null);
        }
      }
      unawaited(_pump());
    });
    await Isolate.spawn(
      _previewWorkerMain,
      <Object>[responses.sendPort, cachedSources],
      debugName: 'AquaRecover preview worker',
      errorsAreFatal: false,
    );
    return ready.future;
  }

  /// Stops the worker. Pending renders fail; a later [render] starts a new
  /// worker.
  void dispose() {
    _commands?.send(null);
    _commands = null;
    _starting = null;
    _responses?.close();
    _responses = null;
    final pending = [..._awaitingReply.values, ..._queue.values];
    _awaitingReply.clear();
    _queue.clear();
    _active = null;
    for (final entry in pending) {
      entry.completeError(StateError('Preview worker stopped.'), null);
    }
  }
}

class _QueuedRender {
  _QueuedRender(this.request) : completers = [Completer<Uint8List>()];

  PreviewRenderRequest request;
  final List<Completer<Uint8List>> completers;

  void complete(Uint8List bytes) {
    for (final completer in completers) {
      completer.complete(bytes);
    }
  }

  void completeError(Object error, StackTrace? stackTrace) {
    for (final completer in completers) {
      completer.completeError(error, stackTrace);
    }
  }
}

Future<void> _previewWorkerMain(List<Object> args) async {
  final replies = args[0] as SendPort;
  final cacheSize = args[1] as int;
  final commands = ReceivePort();
  replies.send(commands.sendPort);
  final sources = _PreviewSourceCache(cacheSize);
  await for (final message in commands) {
    if (message == null) break;
    final request = message as List<Object?>;
    final id = request[0]! as int;
    try {
      final bytes = await renderPreviewBytes(
        PreviewRenderRequest(
          path: request[1]! as String,
          settings: (request[2]! as Map).cast<String, Object?>(),
          lutProfile: (request[3]! as Map).cast<String, Object?>(),
          maxDimension: request[4]! as int,
          jpegQuality: request[5]! as int,
        ),
        sources: sources,
      );
      replies.send(<Object?>[
        id,
        TransferableTypedData.fromList([bytes]),
      ]);
    } on Object catch (error) {
      replies.send(<Object?>[id, error.toString()]);
    }
  }
  commands.close();
}

/// Renders one preview in the current isolate. [sources] lets a long-lived
/// caller reuse decoded, downscaled sources between renders.
Future<Uint8List> renderPreviewBytes(
  PreviewRenderRequest request, {
  PreviewSourceCacheBase? sources,
}) async {
  final source = await (sources ?? const _NoPreviewSourceCache()).load(
    request.path,
    request.maxDimension,
  );
  final restored = const UnderwaterProcessor().restoreImage(
    source,
    RestorationSettings.fromJson(request.settings),
    quality: RestorationRenderQuality.preview,
  );
  final withLut = await const LutService().apply(
    restored,
    LutProfile.fromJson(request.lutProfile),
  );
  return Uint8List.fromList(
    img.encodeJpg(withLut, quality: request.jpegQuality),
  );
}

/// Loads preview-sized sources, optionally from a cache.
abstract class PreviewSourceCacheBase {
  const PreviewSourceCacheBase();

  Future<img.Image> load(String path, int maxDimension);

  static Future<img.Image> decodeForPreview(
    String path,
    int maxDimension,
  ) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('Image not found.', path);
    }
    final decoded = img.decodeImage(await file.readAsBytes());
    if (decoded == null) {
      throw const FormatException('Could not decode image preview.');
    }
    return resizeForPreview(decoded, maxDimension);
  }

  static img.Image resizeForPreview(img.Image source, int maxDimension) {
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
}

class _NoPreviewSourceCache extends PreviewSourceCacheBase {
  const _NoPreviewSourceCache();

  @override
  Future<img.Image> load(String path, int maxDimension) =>
      PreviewSourceCacheBase.decodeForPreview(path, maxDimension);
}

class _PreviewSourceCache extends PreviewSourceCacheBase {
  _PreviewSourceCache(this.capacity);

  final int capacity;
  final LinkedHashMap<String, img.Image> _entries =
      LinkedHashMap<String, img.Image>();

  @override
  Future<img.Image> load(String path, int maxDimension) async {
    final stat = await File(path).stat();
    final key =
        '$path|$maxDimension|${stat.size}|${stat.modified.microsecondsSinceEpoch}';
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return cached;
    }
    final source = await PreviewSourceCacheBase.decodeForPreview(
      path,
      maxDimension,
    );
    _entries[key] = source;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
    return source;
  }
}
