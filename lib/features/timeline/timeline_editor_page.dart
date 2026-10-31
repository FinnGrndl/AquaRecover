import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import '../../shared/widgets/app_tooltip.dart';
import '../../shared/widgets/editor_shortcuts.dart';
import '../../shared/widgets/resizable_split.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../core/media/media_classifier.dart';
import '../../core/models/media_kind.dart';
import '../../core/models/restoration_settings.dart';
import '../../core/photo/photo_library_service.dart';
import '../../core/platform/share_service.dart';
import '../../core/timeline/ffmpeg_timeline_renderer.dart';
import '../../core/timeline/timeline_project.dart';
import '../../core/timeline/timeline_project_store.dart';
import '../../core/timeline/timeline_render_service.dart';
import '../../core/utils/output_paths.dart';
import '../../l10n/l10n.dart';
import '../../l10n/model_labels.dart';
import '../../l10n/timeline_labels.dart';
import '../../shared/widgets/ocean_backdrop.dart';
import '../editor/widgets/editor_bottom_panel.dart';
import '../editor/widgets/editor_glass_surface.dart';
import '../editor/widgets/glass_navigation_bar.dart';
import '../library/export_library_page.dart';
import 'timeline_controller.dart';
import 'timeline_media_picker.dart';
import 'timeline_theme.dart';
import 'widgets/timeline_panels.dart';
import 'widgets/timeline_strip.dart';
import 'widgets/timeline_toolbar.dart';
import 'widgets/timeline_viewer.dart';
import 'widgets/tools/audio_panel.dart';
import 'widgets/tools/effects_panel.dart';
import 'widgets/tools/fade_panel.dart';
import 'widgets/tools/format_panel.dart';
import 'widgets/tools/more_panel.dart';
import 'widgets/tools/motion_panel.dart';
import 'widgets/tools/overlay_panels.dart';
import 'widgets/tools/speed_panel.dart';
import 'widgets/tools/text_panel.dart';
import 'widgets/tools/tool_controls.dart';
import 'widgets/tools/transition_panel.dart';
import 'widgets/tools/volume_panel.dart';
import 'widgets/viewer_selection_overlay.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/share_failed_dialog.dart';

/// The movie editor, laid out like CapCut and dressed like iOS: the viewer
/// on top, transport, a multi-lane timeline with a centred playhead, one
/// floating tool panel at a time, and a toolbar that follows the selection.
/// On wide screens the panel becomes an inspector column beside the viewer.
class TimelineEditorPage extends StatefulWidget {
  const TimelineEditorPage({
    super.key,
    required this.project,
    this.store,
    this.renderService,
    this.mediaPicker,
    this.overlayPicker,
    this.audioPicker,
    this.overlayProbe,
    this.audioProbe,
    this.exportDirectory,
    this.shareService = const ShareService(),
    this.initialMedia = const [],
    this.today,
  });

  final TimelineProject project;
  final TimelineProjectStore? store;
  final TimelineRenderService? renderService;

  /// Overrides the system file picker in widget tests.
  final Future<List<String>> Function()? mediaPicker;

  /// Overrides the picker for picture-in-picture media; defaults to
  /// [mediaPicker], then the system picker.
  final Future<List<String>> Function()? overlayPicker;

  /// Overrides the music picker in widget tests.
  final Future<List<String>> Function()? audioPicker;

  /// Overrides how an overlay's shape and length are read.
  final Future<OverlayMediaInfo> Function(String path)? overlayProbe;

  /// Overrides how a sound's length is read.
  final Future<double?> Function(String path)? audioProbe;

  /// Overrides where rendered movies go, so widget tests need no real
  /// file system.
  final Future<Directory> Function()? exportDirectory;

  /// Opens the system share sheet for a rendered movie.
  final ShareService shareService;

  /// Media picked before the editor opened, added on start.
  final List<String> initialMedia;

  /// The date a Dive stamp title shows; today unless a test fixes it.
  final DateTime? today;

  /// Width from which the tool panel becomes an inspector column.
  static const wideLayoutWidth = 760.0;

  /// Width from which a landscape window uses the inspector column too.
  static const landscapeLayoutWidth = 560.0;

  /// Below this height a landscape window puts the viewer beside the
  /// controls instead of above them.
  static const sideBySideMaxHeight = 500.0;

  @override
  State<TimelineEditorPage> createState() => _TimelineEditorPageState();
}

/// Tools that open a panel and stay valid without a selection.
const _rootPanels = {'audio', 'effects', 'format'};

class _TimelineEditorPageState extends State<TimelineEditorPage>
    with SingleTickerProviderStateMixin {
  late final TimelineController _controller;
  late final TimelineRenderService _renderer;
  late final Ticker _ticker;
  final _zoom = TimelineZoom();

  /// The open panel's tool id, or null when the panel is closed.
  String? _tool;

  /// The junction the Transition panel edits.
  int? _junction;

  /// Focuses the title text field when the Text panel opens.
  bool _textAutofocus = false;

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
    if (widget.initialMedia.isNotEmpty) {
      unawaited(_addPaths(widget.initialMedia));
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _messageTimer?.cancel();
    _zoom.dispose();
    unawaited(_controller.flush().catchError((Object _) {}));
    _controller.dispose();
    super.dispose();
  }

  // Playback ---------------------------------------------------------------

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
    if (mounted && _playing) setState(() => _playing = false);
  }

  // Messages ---------------------------------------------------------------

  /// Shows a short confirmation in the toast. Errors go to [_showError], so
  /// they never vanish on a timer.
  void _say(String message) {
    _messageTimer?.cancel();
    setState(() => _message = message);
    _messageTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _message = null);
    });
  }

  Future<void> _showError(String title, String message) {
    _messageTimer?.cancel();
    if (_message != null) setState(() => _message = null);
    return showAppDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(message),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.ok),
          ),
        ],
      ),
    );
  }

  String _friendly(Object error) => localizedErrorMessage(context.l10n, error);

  // Adding media -----------------------------------------------------------

  Future<void> _addMedia() async {
    _stop();
    final paths = await (widget.mediaPicker ?? pickTimelineMedia)();
    if (paths.isEmpty || !mounted) return;
    await _addPaths(paths);
  }

  Future<void> _addPaths(List<String> paths) async {
    final durations = <String, double>{};
    for (final path in paths) {
      final seconds = await probeVideoDuration(path);
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
      await _showError(
        context.l10n.someFilesSkipped,
        context.l10n.filesNotOnTimeline(skipped.length),
      );
    }
  }

  Future<void> _addOverlay() async {
    _stop();
    final picker =
        widget.overlayPicker ?? widget.mediaPicker ?? pickTimelineMedia;
    final paths = await picker();
    if (paths.isEmpty || !mounted) return;
    final path = paths.first;
    MediaKind? kind;
    try {
      kind = MediaClassifier.classify(path);
    } on UnsupportedError {
      kind = null;
    }
    if (kind == null || kind == MediaKind.rawVideo) {
      await _showError(
        context.l10n.cannotAddOverlay,
        context.l10n.cannotAddOverlayBody,
      );
      return;
    }
    final info = await (widget.overlayProbe ?? probeOverlayMedia)(path);
    if (!mounted) return;
    _controller.addOverlay(
      path: path,
      kind: kind == MediaKind.video ? OverlayKind.video : OverlayKind.image,
      mediaAspect: info.aspect,
      sourceDuration: info.duration,
    );
    setState(() => _tool = null);
  }

  Future<void> _addMusic() async {
    _stop();
    final paths = await (widget.audioPicker ?? pickTimelineAudio)();
    if (paths.isEmpty || !mounted) return;
    final path = paths.first;
    final seconds = await (widget.audioProbe ?? probeAudioDuration)(path);
    if (!mounted) return;
    _controller.addAudio(
      path: path,
      name: p.basenameWithoutExtension(path),
      sourceDuration: seconds,
    );
    setState(() => _tool = null);
  }

  Future<void> _replaceClip() async {
    _stop();
    final paths = await (widget.mediaPicker ?? pickTimelineMedia)();
    if (paths.isEmpty || !mounted) return;
    final seconds = await probeVideoDuration(paths.first);
    if (!mounted) return;
    if (!_controller.replaceSelectedClip(paths.first, videoDuration: seconds)) {
      await _showError(
        context.l10n.cannotReplaceClip,
        context.l10n.cannotReplaceClipBody,
      );
    }
  }

  void _addTitle() {
    _stop();
    _controller.addTitle(text: context.l10n.defaultTitleText);
    setState(() {
      _tool = 'text';
      _textAutofocus = true;
    });
  }

  void _editTitle(String id) {
    _controller.select(id);
    setState(() {
      _tool = 'text';
      _textAutofocus = true;
    });
  }

  // Export -----------------------------------------------------------------

  Future<String> _outputPathFor(TimelineProject project) async {
    final dir = await (widget.exportDirectory ?? OutputPaths.outputDirectory)();
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
    final l10n = context.l10n;
    if (project.clips.isEmpty) {
      await _showError(l10n.nothingToExport, l10n.nothingToExportBody);
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
      _say(l10n.movieSaved);
    } on TimelineRenderCancelled {
      _say(l10n.renderCancelled);
    } on Object catch (error) {
      if (!mounted) return;
      // The Export panel behind the alert drops the failed render's
      // progress right away, not only after OK.
      setState(() => _rendering = false);
      await _showError(l10n.exportFailed, _friendly(error));
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  Future<void> _saveToPhotos() async {
    final path = _outputPath;
    if (path == null) return;
    final l10n = context.l10n;
    try {
      await const PhotoLibraryService().saveExport(path, MediaKind.video);
      _say(l10n.savedToPhotos);
    } on Object catch (error) {
      if (mounted) await _showError(l10n.notSavedToPhotos, _friendly(error));
    }
  }

  bool get _canSaveToPhotos =>
      Platform.isIOS || Platform.isMacOS || Platform.isAndroid;

  Future<void> _shareMovie(Rect? origin) async {
    final path = _outputPath;
    if (path == null) return;
    try {
      await widget.shareService.shareFiles([path], origin: origin);
    } on Object catch (error) {
      if (mounted) await showShareFailedDialog(context, error);
    }
  }

  String? get _backendNote => switch (_renderer.backend) {
    TimelineRenderBackend.android => context.l10n.backendNoteAndroid,
    TimelineRenderBackend.none => context.l10n.backendNoteNoFfmpeg,
    _ => null,
  };

  Future<void> _rename() async {
    final field = TextEditingController(text: _controller.project.name);
    final l10n = context.l10n;
    final name = await showAppDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(l10n.movieName),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(controller: field, autofocus: true),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(field.text.trim()),
            child: Text(l10n.rename),
          ),
        ],
      ),
    );
    field.dispose();
    if (name != null && name.isNotEmpty) {
      _controller.updateProject((p) => p.copyWith(name: name));
    }
  }

  // Tools ------------------------------------------------------------------

  /// Opens [tool]'s panel, or closes it when it is already open.
  void _toggle(String tool) {
    _stop();
    setState(() {
      if (_tool == tool) {
        _tool = null;
      } else {
        _tool = tool;
        _textAutofocus = false;
      }
    });
  }

  void _split() {
    _stop();
    if (!_controller.splitSelected()) {
      unawaited(
        _showError(
          context.l10n.cannotSplitHere,
          context.l10n.cannotSplitHereBody,
        ),
      );
    }
  }

  void _delete() {
    _controller.deleteSelected();
    setState(() => _tool = null);
  }

  void _back() {
    _controller.deselect();
    setState(() => _tool = null);
  }

  TimelineToolItem _item(
    String id,
    IconData icon,
    String label, {
    VoidCallback? onPressed,
    bool panel = true,
    bool destructive = false,
    Key? key,
  }) => TimelineToolItem(
    id: id,
    key: key,
    icon: icon,
    label: label,
    active: panel && _tool == id,
    destructive: destructive,
    onPressed: onPressed ?? (panel ? () => _toggle(id) : null),
  );

  List<TimelineToolItem> _toolbarItems() {
    final selection = _controller.selection;
    final empty = _controller.project.clips.isEmpty;
    final l10n = context.l10n;
    final split = _item(
      'split',
      CupertinoIcons.scissors,
      l10n.toolSplit,
      panel: false,
      key: const Key('timeline_split'),
      onPressed: _split,
    );
    final duplicate = _item(
      'duplicate',
      CupertinoIcons.plus_square_on_square,
      l10n.toolDuplicate,
      panel: false,
      onPressed: _controller.duplicateSelected,
    );
    final delete = _item(
      'delete',
      CupertinoIcons.trash,
      l10n.toolDelete,
      panel: false,
      destructive: true,
      key: const Key('timeline_delete'),
      onPressed: _delete,
    );
    final effects = _item('effects', CupertinoIcons.sparkles, l10n.toolEffects);
    final color = _item(
      'color',
      CupertinoIcons.color_filter,
      l10n.toolColorGrade,
    );
    final fade = _item(
      'fade',
      CupertinoIcons.circle_lefthalf_fill,
      l10n.toolFade,
    );
    final speed = _item('speed', CupertinoIcons.speedometer, l10n.toolSpeed);
    final volume = _item(
      'volume',
      CupertinoIcons.speaker_2_fill,
      l10n.toolVolume,
    );
    final duration = _item('duration', CupertinoIcons.timer, l10n.toolDuration);
    final opacity = _item(
      'opacity',
      CupertinoIcons.circle_righthalf_fill,
      l10n.toolOpacity,
    );
    final animation = _item(
      'animation',
      CupertinoIcons.wand_stars,
      l10n.toolAnimate,
    );
    final layer = _item(
      'layer',
      CupertinoIcons.square_stack_3d_up,
      l10n.toolLayer,
    );
    switch (selection) {
      case NoSelection():
        return [
          _item(
            'edit',
            CupertinoIcons.scissors,
            l10n.toolEdit,
            panel: false,
            onPressed: empty
                ? null
                : () {
                    _stop();
                    _controller.selectClipAtPlayhead();
                  },
          ),
          _item(
            'audio',
            CupertinoIcons.music_note_2,
            l10n.toolAudio,
            onPressed: empty ? null : () => _toggle('audio'),
          ),
          _item(
            'text',
            CupertinoIcons.textformat,
            l10n.toolText,
            panel: false,
            onPressed: empty ? null : _addTitle,
          ),
          _item(
            'overlay',
            CupertinoIcons.rectangle_on_rectangle,
            l10n.toolOverlay,
            panel: false,
            onPressed: empty ? null : _addOverlay,
          ),
          _item(
            'effects',
            CupertinoIcons.sparkles,
            l10n.toolEffects,
            onPressed: empty ? null : () => _toggle('effects'),
          ),
          _item('format', CupertinoIcons.crop, l10n.toolFormat),
        ];
      case ClipSelection():
        final video = _controller.selectedClip?.isVideo ?? false;
        return [
          split,
          if (video) ...[
            speed,
            volume,
          ] else ...[
            duration,
            _item('motion', CupertinoIcons.move, l10n.toolMotion),
          ],
          effects,
          color,
          fade,
          duplicate,
          delete,
          _item('more', CupertinoIcons.ellipsis, l10n.toolMore),
        ];
      case OverlaySelection():
        final overlay = _controller.selectedOverlay;
        if (overlay?.title != null) {
          return [
            _item(
              'text',
              CupertinoIcons.textformat,
              l10n.toolEdit,
              onPressed: () => setState(() {
                _tool = _tool == 'text' ? null : 'text';
                _textAutofocus = _tool == 'text';
              }),
            ),
            opacity,
            animation,
            layer,
            split,
            duplicate,
            delete,
          ];
        }
        final video = overlay?.isVideo ?? false;
        return [
          split,
          if (video) ...[speed, volume] else duration,
          effects,
          color,
          opacity,
          animation,
          layer,
          duplicate,
          delete,
        ];
      case AudioSelection():
        return [volume, fade, split, duplicate, delete];
    }
  }

  /// The open panel's tool, or null when it does not fit the selection.
  String? _openTool(List<TimelineToolItem> items) {
    final tool = _tool;
    if (tool == null) return null;
    if (_controller.project.clips.isEmpty && tool != 'format') return null;
    if (tool == 'text') {
      return _controller.selectedOverlay?.title != null ? tool : null;
    }
    if (tool == 'transition') {
      final index = _junction;
      final clips = _controller.project.clips.length;
      return index != null && index > 0 && index < clips ? tool : null;
    }
    if (tool == 'export') return tool;
    if (items.any((i) => i.id == tool)) return tool;
    // Effects and Audio work from the root toolbar too.
    if (_controller.selection.isNone && _rootPanels.contains(tool)) {
      return tool;
    }
    return null;
  }

  Widget _panelBody(String tool) {
    final c = _controller;
    return switch (tool) {
      'speed' => SpeedPanel(controller: c),
      'duration' => DurationPanel(controller: c),
      'motion' => MotionPanel(controller: c),
      'volume' => VolumePanel(controller: c),
      'fade' => FadePanel(controller: c),
      'effects' => EffectsPanel(controller: c),
      'color' => ColorPanel(controller: c),
      'opacity' => OpacityPanel(controller: c),
      'animation' => AnimationPanel(controller: c),
      'layer' => LayerPanel(controller: c),
      'format' => FormatPanel(controller: c),
      'audio' => AudioAddPanel(controller: c, onPickMusic: _addMusic),
      'more' => MorePanel(
        controller: c,
        onReplace: _replaceClip,
        onError: _showError,
      ),
      'transition' => TransitionPanel(controller: c, clipIndex: _junction!),
      'text' => TextPanel(
        key: ValueKey('text-${c.selection.id}'),
        controller: c,
        overlayId: c.selection.id!,
        autofocus: _textAutofocus,
        today: widget.today,
        onDone: () => setState(() => _tool = null),
      ),
      'export' => Column(
        children: [
          ToolHeader(title: context.l10n.exportTitle),
          Expanded(
            child: DeliverPanel(
              controller: c,
              rendering: _rendering,
              progress: _progress,
              outputPath: _outputPath,
              backendNote: _backendNote,
              onRender: _renderer.backend == TimelineRenderBackend.none
                  ? null
                  : _render,
              onCancel: _renderer.cancel,
              onSaveToPhotos: _canSaveToPhotos ? _saveToPhotos : null,
              onShare: widget.shareService.isAvailable ? _shareMovie : null,
              onOpenLibrary: () => Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (_) =>
                      ExportLibraryPage(shareService: widget.shareService),
                ),
              ),
            ),
          ),
        ],
      ),
      _ => const SizedBox.shrink(),
    };
  }

  static double _preferredHeight(String tool) => switch (tool) {
    'speed' => 200,
    'duration' => 176,
    'motion' => 150,
    'volume' => 196,
    'fade' => 250,
    'effects' => 264,
    'color' => 316,
    'opacity' => 150,
    'animation' => 196,
    'layer' => 160,
    'format' => 150,
    'audio' => 214,
    'more' => 300,
    'transition' => 256,
    'text' => 318,
    'export' => 360,
    _ => 220,
  };

  String _toolLabel(String tool, List<TimelineToolItem> items) {
    for (final item in items) {
      if (item.id == tool) return item.label;
    }
    return switch (tool) {
      'export' => context.l10n.exportTitle,
      'transition' => context.l10n.toolTransition,
      'text' => context.l10n.toolText,
      _ => tool,
    };
  }

  void _openJunction(int index) {
    _stop();
    setState(() {
      if (_tool == 'transition' && _junction == index) {
        _tool = null;
      } else {
        _junction = index;
        _tool = 'transition';
      }
    });
  }

  // Layout -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Read here: inside the page scaffold, which resizes for the keyboard,
    // the keyboard's inset is already removed.
    _keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return TimelineTheme(
      child: CupertinoPageScaffold(
        backgroundColor: TimelineColors.background,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: OceanBackdrop(
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: EditorShortcuts(
                canUndo: () => _controller.canUndo && !_rendering,
                onUndo: _controller.undo,
                canRedo: () => _controller.canRedo && !_rendering,
                onRedo: _controller.redo,
                onPlayPause: _togglePlay,
                // Escape closes the open panel, then clears the selection.
                canEscape: () => _tool != null || !_controller.selection.isNone,
                onEscape: () {
                  if (_tool != null) {
                    setState(() => _tool = null);
                  } else {
                    _back();
                  }
                },
                child: ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => LayoutBuilder(builder: _layout),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const _minViewerHeight = 150.0;

  bool _keyboardOpen = false;

  Widget _layout(BuildContext context, BoxConstraints constraints) {
    final insets = MediaQuery.paddingOf(context);
    final keyboard = _keyboardOpen;
    // Landscape phones use the inspector layout too: below the viewer there
    // is no height left for a tool panel.
    final wide =
        constraints.maxWidth >= TimelineEditorPage.wideLayoutWidth ||
        (constraints.maxWidth > constraints.maxHeight &&
            constraints.maxWidth >= TimelineEditorPage.landscapeLayoutWidth);
    final gutter = wide ? 20.0 : 12.0;
    final items = _toolbarItems();
    final tool = _openTool(items);
    final project = _controller.project;
    final empty = project.clips.isEmpty;
    final topBar = Padding(
      padding: EdgeInsets.fromLTRB(gutter, insets.top + 8, gutter, 6),
      child: _topBar(),
    );
    // Keys keep each part's state (toolbar scroll, timeline scroll) when a
    // panel appears above it.
    final toolbar = Padding(
      key: const ValueKey('toolbar'),
      padding: EdgeInsets.fromLTRB(
        gutter - 6,
        0,
        gutter - 6,
        insets.bottom + (wide ? 12 : 6),
      ),
      child: TimelineToolbar(
        items: items,
        semanticLabel: _controller.selection.isNone
            ? context.l10n.movieTools
            : context.l10n.itemTools(selectionName(context.l10n, _controller)),
        onBack: _controller.selection.isNone ? null : _back,
        backLabel: context.l10n.done,
      ),
    );
    Widget panel(double height, {bool animate = true}) => GlassBottomPanel(
      label: context.l10n.itemTools(_toolLabel(tool!, items)),
      open: true,
      height: height,
      animate: animate,
      scrollable: false,
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      onClose: () => setState(() => _tool = null),
      child: KeyedSubtree(key: ValueKey(tool), child: _panelBody(tool)),
    );
    TimelineStrip strip({bool compact = false}) => TimelineStrip(
      key: const ValueKey('strip'),
      controller: _controller,
      zoom: _zoom,
      compact: compact,
      onScrubStart: _stop,
      onAdd: empty ? null : _addMedia,
      onAddText: empty ? null : _addTitle,
      onAddOverlay: empty ? null : _addOverlay,
      onAddAudio: empty ? null : () => _toggle('audio'),
      onJunction: _openJunction,
      activeJunction: tool == 'transition' ? _junction : null,
    );

    if (_sideBySide(constraints)) {
      return _sideBySideLayout(
        constraints,
        insets: insets,
        topBar: _topBar(),
        toolbar: toolbar,
        tool: tool,
        panel: panel,
        strip: strip,
      );
    }

    if (wide) {
      // Short windows (landscape phones, small Mac and Windows windows)
      // shrink the timeline to its thin overview so the viewer keeps some
      // room and the toolbar stays on screen; very short ones hide it.
      final fixedWide =
          insets.top +
          62 + // top bar
          52 + // transport
          8 +
          (empty ? 12 : TimelineToolbar.height + 12) +
          insets.bottom;
      final roomWide = constraints.maxHeight - fixedWide;
      final compactWide =
          roomWide - TimelineStrip.heightOf(project) < _minViewerHeight;
      final hideStripWide =
          roomWide - TimelineStrip.heightOf(project, compact: true) < 48;
      // Below the viewer: transport, gap and toolbar, then the strip.
      final restWide = fixedWide - insets.top - 62;
      final stripWide = hideStripWide
          ? 0.0
          : TimelineStrip.heightOf(project, compact: compactWide);
      return Column(
        children: [
          topBar,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ResizableSplit(
                    axis: Axis.vertical,
                    memoryKey: 'movie.stacked',
                    defaultExtent: (total) => total - restWide - stripWide,
                    minRest: restWide,
                    settle: (extent, total, {required growing}) =>
                        _settleStrip(extent, total - restWide, growing),
                    handleBias: -1,
                    gripOffset: -3,
                    builder: (context, extent, rest, resizing) {
                      return Column(
                        children: [
                          SizedBox(height: extent, child: _viewerArea()),
                          _transport(gutter, showZoom: true),
                          ?_stripFor(rest - restWide, strip).strip,
                          const Spacer(),
                          const SizedBox(height: 8),
                          if (empty)
                            SizedBox(height: insets.bottom + 12)
                          else
                            toolbar,
                        ],
                      );
                    },
                  ),
                ),
                if (tool != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      0,
                      0,
                      gutter - 6,
                      insets.bottom + 12,
                    ),
                    child: SizedBox(
                      // Wide enough for the export settings in small
                      // windows and landscape phones.
                      width: math.min(
                        400,
                        math.max(300, constraints.maxWidth * .36),
                      ),
                      child: panel(double.infinity),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    if (keyboard && tool == 'text') {
      // Typing: only the viewer and the text panel, above the keyboard.
      return Column(
        children: [
          topBar,
          Expanded(child: _viewerArea()),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter - 6),
            child: panel(math.min(260, constraints.maxHeight * .5)),
          ),
        ],
      );
    }

    // Phone: the panel takes what its tool needs, the viewer keeps the
    // rest, and the timeline shrinks to a thin overview when room runs out.
    final available = constraints.maxHeight;
    final panelHeight = tool == null
        ? 0.0
        : math.min(_preferredHeight(tool), math.max(150.0, available * .34));
    final fixed =
        insets.top +
        60 + // top bar
        52 + // transport
        6 +
        (empty ? 0 : TimelineToolbar.height) +
        insets.bottom +
        6 +
        (tool == null ? 0 : panelHeight + 7);
    final compact =
        available - fixed - TimelineStrip.heightOf(project) < _minViewerHeight;
    // With a panel open the strip gives way early; without one only when
    // the window is so short (a keyboard on iPhone SE, say) that even the
    // thin overview would push the toolbar off screen.
    final hideStrip =
        compact &&
        available - fixed - TimelineStrip.heightOf(project, compact: true) <
            (tool != null ? 110 : 48);

    // Below the viewer: transport, gaps, the panel's margin and the
    // toolbar; then the strip and the panel.
    final rest = fixed - insets.top - 60 - (tool == null ? 0 : panelHeight);
    final defaultStrip = hideStrip
        ? 0.0
        : TimelineStrip.heightOf(project, compact: compact);
    return Column(
      children: [
        topBar,
        Expanded(
          child: ResizableSplit(
            axis: Axis.vertical,
            memoryKey: 'movie.stacked',
            defaultExtent: (total) => total - rest - panelHeight - defaultStrip,
            minRest: rest + math.min(panelHeight, 150),
            // An open panel takes up any slack itself.
            settle: tool != null
                ? null
                : (extent, total, {required growing}) =>
                      _settleStrip(extent, total - rest, growing),
            handleBias: -1,
            gripOffset: -3,
            builder: (context, extent, room, resizing) {
              // The strip gives way before the panel shrinks; a smaller
              // viewer leaves the panel more.
              final shown = _stripFor(room - rest - panelHeight, strip);
              return Column(
                children: [
                  SizedBox(height: extent, child: _viewerArea()),
                  _transport(gutter, showZoom: constraints.maxWidth >= 370),
                  ?shown.strip,
                  const SizedBox(height: 6),
                  if (tool != null)
                    Padding(
                      key: const ValueKey('panel'),
                      padding: EdgeInsets.symmetric(horizontal: gutter - 6),
                      child: panel(
                        math.max(0, room - rest - shown.height),
                        animate: !resizing,
                      ),
                    )
                  else
                    const Spacer(),
                  if (empty) SizedBox(height: insets.bottom + 6) else toolbar,
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// Where a viewer of [extent] settles when [room] is what the viewer and
  /// the strip share: between two strip heights it goes on to the next fit
  /// rather than leave a gap above the toolbar.
  double _settleStrip(double extent, double room, bool growing) {
    final project = _controller.project;
    final fits = [
      room - TimelineStrip.heightOf(project),
      room - TimelineStrip.heightOf(project, compact: true),
      room,
    ];
    if (extent <= fits.first) return extent;
    for (final fit in fits) {
      if ((fit - extent).abs() <= .5) return fit;
    }
    for (var i = 0; i < fits.length - 1; i++) {
      if (extent < fits[i + 1]) return growing ? fits[i + 1] : fits[i];
    }
    return extent;
  }

  /// The timeline strip at full height when [room] fits it, else its thin
  /// overview, else none.
  ({TimelineStrip? strip, double height}) _stripFor(
    double room,
    TimelineStrip Function({bool compact}) strip,
  ) {
    final project = _controller.project;
    final full = TimelineStrip.heightOf(project);
    final thin = TimelineStrip.heightOf(project, compact: true);
    // A hair of slack keeps rounding from dropping a strip that fits.
    const slack = 1e-9;
    if (room + slack >= full) return (strip: strip(), height: full);
    if (room + slack >= thin) {
      return (strip: strip(compact: true), height: thin);
    }
    return (strip: null, height: 0);
  }

  /// Landscape phones and other short, wide windows: below a viewer there
  /// is no height left, so the viewer takes the leading side at full height
  /// and the controls stack in a column beside it, as in Photos.
  static bool _sideBySide(BoxConstraints constraints) =>
      constraints.maxWidth > constraints.maxHeight &&
      constraints.maxHeight < TimelineEditorPage.sideBySideMaxHeight &&
      constraints.maxWidth >= TimelineEditorPage.landscapeLayoutWidth;

  Widget _sideBySideLayout(
    BoxConstraints constraints, {
    required EdgeInsets insets,
    required Widget topBar,
    required Widget toolbar,
    required String? tool,
    required Widget Function(double height) panel,
    required TimelineStrip Function({bool compact}) strip,
  }) {
    final project = _controller.project;
    final empty = project.clips.isEmpty;
    final usable = constraints.maxWidth - insets.left - insets.right;
    final defaultSideWidth = (usable * .4).clamp(300.0, 400.0).toDouble();
    const barHeight = 48.0 + 14;
    const transportHeight = 52.0;
    // The toolbar brings its own bottom padding.
    final toolbarHeight = empty
        ? insets.bottom + 8
        : TimelineToolbar.height + insets.bottom + 16;
    final typing = _keyboardOpen && tool == 'text';
    final room =
        constraints.maxHeight -
        insets.top -
        barHeight -
        (typing ? 0 : transportHeight + toolbarHeight);
    // An open panel gets the transport's row too when it would otherwise
    // be too short to use; Space still plays on a keyboard.
    final showTransport = !typing && (tool == null || room >= 200);
    final fullStrip = TimelineStrip.heightOf(project);
    final compactStrip = TimelineStrip.heightOf(project, compact: true);
    final Widget middle;
    if (tool != null) {
      middle = Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: panel(double.infinity),
        ),
      );
    } else if (room >= compactStrip + 4) {
      middle = Expanded(
        child: Align(
          alignment: Alignment.topCenter,
          child: strip(compact: room < fullStrip + 4),
        ),
      );
    } else {
      middle = const Spacer();
    }
    return Padding(
      padding: EdgeInsets.only(left: insets.left, right: insets.right),
      child: ResizableSplit(
        axis: Axis.horizontal,
        memoryKey: 'movie.sideBySide',
        defaultExtent: (total) => total - defaultSideWidth,
        minRest: _minSideWidth,
        // Mostly over the viewer, clear of the column's controls.
        handleBias: -.5,
        builder: (context, extent, sideWidth, resizing) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: extent,
              child: Padding(
                padding: EdgeInsets.only(
                  top: insets.top + 8,
                  bottom: insets.bottom + 8,
                ),
                child: _viewerArea(),
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(4, insets.top + 8, 12, 6),
                    child: topBar,
                  ),
                  if (showTransport)
                    _transport(4, showZoom: !empty && sideWidth >= 380),
                  middle,
                  if (!typing) ...[
                    const SizedBox(height: 4),
                    if (empty) SizedBox(height: insets.bottom + 4) else toolbar,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The least the controls beside a landscape viewer keep.
  static const _minSideWidth = 300.0;

  Widget _topBar() {
    final project = _controller.project;
    final clips = project.clips.length;
    final l10n = context.l10n;
    return GlassNavigationBar(
      leadingKey: const Key('timeline_back'),
      leadingLabel: l10n.movies,
      onLeadingPressed: _rendering
          ? null
          : () => Navigator.of(context).maybePop(),
      title: project.name,
      subtitle: clips == 0
          ? l10n.noClipsYet(project.aspect.labelIn(l10n))
          : l10n.movieSummary(
              clips,
              formatTimecode(project.duration, tenths: false),
              project.aspect.labelIn(l10n),
            ),
      onTitlePressed: _rendering ? null : _rename,
      trailingWidth: 46,
      trailing: AppTooltip(
        message: l10n.exportMovie,
        child: Semantics(
          button: true,
          label: l10n.exportMovie,
          child: CupertinoButton(
            key: const Key('timeline_open_export'),
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            borderRadius: BorderRadius.circular(99),
            color: CupertinoColors.activeBlue,
            disabledColor: CupertinoColors.activeBlue.withValues(alpha: .38),
            onPressed: project.clips.isEmpty ? null : () => _toggle('export'),
            child: Icon(
              CupertinoIcons.share_up,
              color: CupertinoColors.white.withValues(
                alpha: project.clips.isEmpty ? .38 : 1,
              ),
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  Widget _viewerArea() {
    final empty = _controller.project.clips.isEmpty;
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TimelineViewer(
              project: _controller.project,
              plan: _controller.plan,
              playhead: _controller.playhead,
              playing: _playing,
              onVideoDuration: _controller.setSourceDuration,
              canvasOverlay: (context, canvas) => ViewerSelectionOverlay(
                controller: _controller,
                canvasSize: canvas.size,
                onEditTitle: _editTitle,
              ),
            ),
          ),
        ),
        if (empty)
          Positioned.fill(
            child: Center(
              child: SingleChildScrollView(
                // Scrolls in very short windows instead of overflowing.
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.l10n.startWithBestShots,
                      style: const TextStyle(
                        color: TimelineColors.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.startWithBestShotsBody,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: TimelineColors.secondaryText,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 14),
                    CupertinoButton(
                      key: const Key('timeline_empty_add'),
                      color: CupertinoColors.activeBlue,
                      borderRadius: BorderRadius.circular(99),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 11,
                      ),
                      onPressed: _addMedia,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            CupertinoIcons.add,
                            color: CupertinoColors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              context.l10n.addPhotosAndClips,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: CupertinoColors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_message != null)
          Positioned(
            left: 24,
            right: 24,
            bottom: 14,
            child: Semantics(
              liveRegion: true,
              child: Center(
                child: EditorGlassSurface(
                  borderRadius: 16,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
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

  Widget _transport(double gutter, {required bool showZoom}) {
    const tabular = [FontFeature.tabularFigures()];
    final empty = _controller.project.clips.isEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter + 4, 2, gutter, 2),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    label: context.l10n.playheadOf(
                      formatTimecode(_controller.playhead),
                      formatTimecode(_controller.project.duration),
                    ),
                    excludeSemantics: true,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatTimecode(_controller.playhead),
                          style: const TextStyle(
                            color: TimelineColors.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFeatures: tabular,
                          ),
                        ),
                        Text(
                          formatTimecode(_controller.project.duration),
                          style: const TextStyle(
                            color: TimelineColors.secondaryText,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            fontFeatures: tabular,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (showZoom && !empty) ...[
                    const SizedBox(width: 4),
                    ListenableBuilder(
                      listenable: _zoom,
                      builder: (context, _) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ZoomButton(
                            key: const Key('timeline_zoom_out'),
                            icon: CupertinoIcons.zoom_out,
                            label: context.l10n.zoomOutTimeline,
                            onPressed: _zoom.canZoomOut ? _zoom.zoomOut : null,
                          ),
                          _ZoomButton(
                            key: const Key('timeline_zoom_in'),
                            icon: CupertinoIcons.zoom_in,
                            label: context.l10n.zoomInTimeline,
                            onPressed: _zoom.canZoomIn ? _zoom.zoomIn : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            GlassIconButton(
              key: const Key('timeline_play'),
              icon: _playing
                  ? CupertinoIcons.pause_fill
                  : CupertinoIcons.play_fill,
              label: _playing ? context.l10n.pause : context.l10n.play,
              tooltip: showsShortcutHints
                  ? context.l10n.playPauseShortcut(
                      _playing ? context.l10n.pause : context.l10n.play,
                    )
                  : null,
              size: 48,
              iconSize: 22,
              onPressed: empty ? null : _togglePlay,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GlassIconButton(
                    key: const Key('timeline_undo'),
                    icon: CupertinoIcons.arrow_uturn_left,
                    label: context.l10n.undo,
                    tooltip: withShortcut(context.l10n.undo, 'Z'),
                    iconSize: 17,
                    onPressed: _controller.canUndo && !_rendering
                        ? _controller.undo
                        : null,
                  ),
                  const SizedBox(width: 8),
                  GlassIconButton(
                    key: const Key('timeline_redo'),
                    icon: CupertinoIcons.arrow_uturn_right,
                    label: context.l10n.redo,
                    tooltip: withShortcut(context.l10n.redo, 'Z', shift: true),
                    iconSize: 17,
                    onPressed: _controller.canRedo && !_rendering
                        ? _controller.redo
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A plain 44 pt zoom button beside the timecode.
class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AppTooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: label,
        excludeSemantics: true,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          onPressed: onPressed,
          child: Icon(
            icon,
            size: 20,
            color: TimelineColors.text.withValues(
              alpha: onPressed == null ? .3 : .85,
            ),
          ),
        ),
      ),
    );
  }
}
