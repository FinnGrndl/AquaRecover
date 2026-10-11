import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../../core/media/media_classifier.dart';
import '../../core/models/media_kind.dart';
import '../../core/models/restoration_settings.dart';
import '../../core/photo/photo_library_service.dart';
import '../../core/timeline/ffmpeg_timeline_renderer.dart';
import '../../core/timeline/timeline_project.dart';
import '../../core/timeline/timeline_project_store.dart';
import '../../core/timeline/timeline_render_service.dart';
import '../../core/utils/output_paths.dart';
import '../library/export_library_page.dart';
import 'timeline_controller.dart';
import 'timeline_theme.dart';
import 'widgets/timeline_panels.dart';
import 'widgets/timeline_strip.dart';
import 'widgets/timeline_viewer.dart';

enum TimelinePage { cut, color, deliver }

/// A compact, Resolve-style movie editor: viewer on top, a centred-playhead
/// timeline, and Cut / Color / Deliver pages that fit a phone in portrait.
class TimelineEditorPage extends StatefulWidget {
  const TimelineEditorPage({
    super.key,
    required this.project,
    this.store,
    this.renderService,
    this.mediaPicker,
  });

  final TimelineProject project;
  final TimelineProjectStore? store;
  final TimelineRenderService? renderService;

  /// Overrides the system file picker in widget tests.
  final Future<List<String>> Function()? mediaPicker;

  @override
  State<TimelineEditorPage> createState() => _TimelineEditorPageState();
}

class _TimelineEditorPageState extends State<TimelineEditorPage>
    with SingleTickerProviderStateMixin {
  late final TimelineController _controller;
  late final TimelineRenderService _renderer;
  late final Ticker _ticker;
  TimelinePage _page = TimelinePage.cut;
  bool _playing = false;
  Duration _lastTick = Duration.zero;
  bool _rendering = false;
  double _progress = 0;
  String? _outputPath;
  String? _message;
  Timer? _messageTimer;

  @override
  void initState() {
    super.initState();
    _controller = TimelineController(widget.project, store: widget.store);
    _renderer = widget.renderService ?? TimelineRenderService();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _messageTimer?.cancel();
    unawaited(_controller.flush().catchError((Object _) {}));
    _controller.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final delta = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    final next = _controller.playhead + delta;
    if (next >= _controller.project.duration) {
      _controller.seek(_controller.project.duration);
      _stop();
      return;
    }
    _controller.seek(next);
  }

  void _togglePlay() {
    if (_playing) {
      _stop();
      return;
    }
    if (_controller.project.clips.isEmpty) return;
    if (_controller.playhead >= _controller.project.duration - 0.05) {
      _controller.seek(0);
    }
    _lastTick = Duration.zero;
    setState(() => _playing = true);
    _ticker.start();
  }

  void _stop() {
    _ticker.stop();
    if (mounted) setState(() => _playing = false);
  }

  void _say(String message) {
    _messageTimer?.cancel();
    setState(() => _message = message);
    _messageTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _message = null);
    });
  }

  Future<List<String>> _pickMedia() async {
    final picker = widget.mediaPicker;
    if (picker != null) return picker();
    final result = await FilePicker.platform.pickFiles(
      type: Platform.isIOS || Platform.isAndroid
          ? FileType.media
          : FileType.custom,
      allowedExtensions: Platform.isIOS || Platform.isAndroid
          ? null
          : [
              ...MediaClassifier.imageExtensions,
              ...MediaClassifier.rawPhotoExtensions,
              ...MediaClassifier.videoExtensions,
            ],
      allowMultiple: true,
    );
    return result?.files.map((f) => f.path).whereType<String>().toList() ??
        const [];
  }

  Future<void> _addMedia() async {
    _stop();
    final paths = await _pickMedia();
    if (paths.isEmpty || !mounted) return;
    final durations = <String, double>{};
    for (final path in paths) {
      final seconds = await _videoDuration(path);
      if (seconds != null) durations[path] = seconds;
    }
    if (!mounted) return;
    final selected = _controller.selectedClip;
    final skipped = _controller.addMedia(
      paths,
      videoDurations: durations,
      grade: selected?.grade ?? const RestorationSettings(),
    );
    if (skipped.isNotEmpty) {
      _say(
        'Skipped ${skipped.length} file${skipped.length == 1 ? '' : 's'} '
        'that cannot go on a timeline (RAW video or unknown type).',
      );
    }
  }

  static Future<double?> _videoDuration(String path) async {
    final MediaKind kind;
    try {
      kind = MediaClassifier.classify(path);
    } on UnsupportedError {
      return null;
    }
    if (kind != MediaKind.video) return null;
    final player = VideoPlayerController.file(File(path));
    try {
      await player.initialize().timeout(const Duration(seconds: 8));
      final seconds = player.value.duration.inMicroseconds / 1e6;
      return seconds > 0 ? seconds : null;
    } on Object {
      return null;
    } finally {
      unawaited(player.dispose());
    }
  }

  Future<String> _outputPathFor(TimelineProject project) async {
    final dir = await OutputPaths.outputDirectory();
    final stem = project.name
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]+'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .substring(0, 19);
    return p.join(
      dir.path,
      '${stem.isEmpty ? 'AquaRecover movie' : stem} $stamp.mp4',
    );
  }

  Future<void> _render() async {
    _stop();
    final project = _controller.project;
    if (project.clips.isEmpty) {
      _say('Add at least one photo or clip first.');
      return;
    }
    setState(() {
      _rendering = true;
      _progress = 0;
      _outputPath = null;
    });
    try {
      await _controller.flush().catchError((Object _) {});
      final output = await _outputPathFor(project);
      final path = await _renderer.render(
        project,
        outputPath: output,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      if (!mounted) return;
      setState(() => _outputPath = path);
      unawaited(HapticFeedback.mediumImpact());
      _say('Movie saved to your AquaRecover exports.');
    } on TimelineRenderCancelled {
      _say('Render cancelled.');
    } on Object catch (error) {
      _say(_friendly(error));
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  Future<void> _saveToPhotos() async {
    final path = _outputPath;
    if (path == null) return;
    try {
      await const PhotoLibraryService().saveExport(path, MediaKind.video);
      _say('Saved to Photos.');
    } on Object catch (error) {
      _say(_friendly(error));
    }
  }

  static String _friendly(Object error) {
    final text = error.toString().replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return text.length <= 220 ? text : '${text.substring(0, 220)}…';
  }

  Future<void> _rename() async {
    final field = TextEditingController(text: _controller.project.name);
    final name = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Movie name'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(controller: field, autofocus: true),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(field.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    field.dispose();
    if (name != null && name.isNotEmpty) {
      _controller.updateProject((p) => p.copyWith(name: name));
    }
  }

  bool get _canSaveToPhotos =>
      Platform.isIOS || Platform.isMacOS || Platform.isAndroid;

  String? get _backendNote => switch (TimelineRenderService.currentBackend) {
    TimelineRenderBackend.android => 'fades render as dips to black',
    TimelineRenderBackend.none => 'needs ffmpeg on this computer',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    return CupertinoTheme(
      data: const CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: TimelineColors.accent,
        scaffoldBackgroundColor: TimelineColors.background,
      ),
      child: CupertinoPageScaffold(
        backgroundColor: TimelineColors.background,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: SafeArea(
            bottom: false,
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 900;
                  final viewer = _viewerArea();
                  final panel = _panelArea(wide: wide);
                  if (wide) {
                    return Column(
                      children: [
                        _topBar(),
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    Expanded(child: viewer),
                                    _transport(),
                                    _strip(),
                                  ],
                                ),
                              ),
                              SizedBox(width: 380, child: panel),
                            ],
                          ),
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      _topBar(),
                      Expanded(child: viewer),
                      _transport(),
                      _strip(),
                      SizedBox(
                        height: (constraints.maxHeight * .40).clamp(
                          230.0,
                          340.0,
                        ),
                        child: panel,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    final project = _controller.project;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Row(
        children: [
          CupertinoButton(
            key: const Key('timeline_back'),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            onPressed: _rendering
                ? null
                : () => Navigator.of(context).maybePop(),
            child: const Icon(
              CupertinoIcons.chevron_back,
              color: TimelineColors.text,
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: _rendering ? null : _rename,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TimelineColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${project.clips.length} item'
                    '${project.clips.length == 1 ? '' : 's'} · '
                    '${project.aspect.label}',
                    style: const TextStyle(
                      color: TimelineColors.secondaryText,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Undo',
            child: CupertinoButton(
              key: const Key('timeline_undo'),
              padding: const EdgeInsets.all(8),
              onPressed: _controller.canUndo && !_rendering
                  ? _controller.undo
                  : null,
              child: const Icon(CupertinoIcons.arrow_uturn_left, size: 20),
            ),
          ),
          Semantics(
            button: true,
            label: 'Redo',
            child: CupertinoButton(
              padding: const EdgeInsets.all(8),
              onPressed: _controller.canRedo && !_rendering
                  ? _controller.redo
                  : null,
              child: const Icon(CupertinoIcons.arrow_uturn_right, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewerArea() {
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: TimelineViewer(
              project: _controller.project,
              playhead: _controller.playhead,
              playing: _playing,
              onVideoDuration: _controller.setSourceDuration,
            ),
          ),
        ),
        if (_message != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: Semantics(
              liveRegion: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xe6000000),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  child: Text(
                    _message!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: TimelineColors.text,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _transport() {
    const tabular = [FontFeature.tabularFigures()];
    return SizedBox(
      height: 46,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 14,
            child: Text.rich(
              TextSpan(
                text: formatTimecode(_controller.playhead),
                style: const TextStyle(color: TimelineColors.text),
                children: [
                  TextSpan(
                    text: ' / ${formatTimecode(_controller.project.duration)}',
                    style: const TextStyle(color: TimelineColors.secondaryText),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 13, fontFeatures: tabular),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                button: true,
                label: 'Go to start',
                child: CupertinoButton(
                  padding: const EdgeInsets.all(8),
                  onPressed: () => _controller.seek(0),
                  child: const Icon(
                    CupertinoIcons.backward_end_fill,
                    size: 20,
                    color: TimelineColors.text,
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: _playing ? 'Pause' : 'Play',
                child: CupertinoButton(
                  key: const Key('timeline_play'),
                  padding: const EdgeInsets.all(8),
                  onPressed: _controller.project.clips.isEmpty
                      ? null
                      : _togglePlay,
                  child: Icon(
                    _playing
                        ? CupertinoIcons.pause_fill
                        : CupertinoIcons.play_fill,
                    size: 28,
                    color: TimelineColors.text,
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: 'Go to end',
                child: CupertinoButton(
                  padding: const EdgeInsets.all(8),
                  onPressed: () =>
                      _controller.seek(_controller.project.duration),
                  child: const Icon(
                    CupertinoIcons.forward_end_fill,
                    size: 20,
                    color: TimelineColors.text,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _strip() {
    return Container(
      color: TimelineColors.panel,
      child: TimelineStrip(controller: _controller, onScrubStart: _stop),
    );
  }

  Widget _panelArea({required bool wide}) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final body = switch (_page) {
      TimelinePage.cut => CutPanel(
        controller: _controller,
        onAdd: _addMedia,
        onMessage: _say,
      ),
      TimelinePage.color => ColorPanel(controller: _controller),
      TimelinePage.deliver => DeliverPanel(
        controller: _controller,
        rendering: _rendering,
        progress: _progress,
        outputPath: _outputPath,
        backendNote: _backendNote,
        onRender:
            TimelineRenderService.currentBackend == TimelineRenderBackend.none
            ? null
            : _render,
        onCancel: _renderer.cancel,
        onSaveToPhotos: _canSaveToPhotos ? _saveToPhotos : null,
        onOpenLibrary: () => Navigator.of(context).push(
          CupertinoPageRoute<void>(builder: (_) => const ExportLibraryPage()),
        ),
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TimelineColors.panel,
        border: Border(
          top: wide
              ? BorderSide.none
              : const BorderSide(color: TimelineColors.stroke),
          left: wide
              ? const BorderSide(color: TimelineColors.stroke)
              : BorderSide.none,
        ),
      ),
      child: Column(
        children: [
          Expanded(child: body),
          Container(height: 1, color: TimelineColors.stroke),
          Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: SizedBox(
              height: 54,
              child: Row(
                children: [
                  for (final page in TimelinePage.values)
                    Expanded(child: _pageTab(page)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pageTab(TimelinePage page) {
    final selected = _page == page;
    final (icon, label) = switch (page) {
      TimelinePage.cut => (CupertinoIcons.scissors_alt, 'Cut'),
      TimelinePage.color => (CupertinoIcons.color_filter, 'Color'),
      TimelinePage.deliver => (CupertinoIcons.share_up, 'Deliver'),
    };
    final color = selected
        ? TimelineColors.accent
        : TimelineColors.secondaryText;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: CupertinoButton(
        key: Key('timeline_page_${page.name}'),
        padding: EdgeInsets.zero,
        onPressed: () => setState(() => _page = page),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 21, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
