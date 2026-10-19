import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../core/models/media_kind.dart';
import '../../core/models/restoration_settings.dart';
import '../../core/photo/photo_library_service.dart';
import '../../core/timeline/ffmpeg_timeline_renderer.dart';
import '../../core/timeline/timeline_project.dart';
import '../../core/timeline/timeline_project_store.dart';
import '../../core/timeline/timeline_render_service.dart';
import '../../core/utils/output_paths.dart';
import '../../shared/widgets/ocean_backdrop.dart';
import '../editor/widgets/editor_bottom_panel.dart';
import '../editor/widgets/editor_glass_surface.dart';
import '../editor/widgets/editor_tool_rail.dart';
import '../editor/widgets/glass_navigation_bar.dart';
import '../library/export_library_page.dart';
import 'timeline_controller.dart';
import 'timeline_media_picker.dart';
import 'timeline_theme.dart';
import 'widgets/timeline_panels.dart';
import 'widgets/timeline_strip.dart';
import 'widgets/timeline_viewer.dart';

enum TimelinePage {
  edit('Edit', CupertinoIcons.scissors),
  color('Color', CupertinoIcons.color_filter),
  export('Export', CupertinoIcons.share_up);

  const TimelinePage(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The movie editor: viewer on top, a centred-playhead timeline, and Edit,
/// Color, and Export tools in the same floating glass panel and tab bar as
/// the photo editor, so it fits a phone in portrait.
class TimelineEditorPage extends StatefulWidget {
  const TimelineEditorPage({
    super.key,
    required this.project,
    this.store,
    this.renderService,
    this.mediaPicker,
    this.initialMedia = const [],
  });

  final TimelineProject project;
  final TimelineProjectStore? store;
  final TimelineRenderService? renderService;

  /// Overrides the system file picker in widget tests.
  final Future<List<String>> Function()? mediaPicker;

  /// Media picked before the editor opened, added on start.
  final List<String> initialMedia;

  @override
  State<TimelineEditorPage> createState() => _TimelineEditorPageState();
}

class _TimelineEditorPageState extends State<TimelineEditorPage>
    with SingleTickerProviderStateMixin {
  late final TimelineController _controller;
  late final TimelineRenderService _renderer;
  late final Ticker _ticker;
  TimelinePage _page = TimelinePage.edit;
  bool _panelOpen = true;
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
      _say(
        'Skipped ${skipped.length} file${skipped.length == 1 ? '' : 's'} '
        'that cannot go on a timeline (RAW video or unknown type).',
      );
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
      data: timelineTheme(context),
      child: CupertinoPageScaffold(
        backgroundColor: TimelineColors.background,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: OceanBackdrop(
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => LayoutBuilder(
                builder: (context, constraints) {
                  final insets = MediaQuery.paddingOf(context);
                  final wide = constraints.maxWidth >= 900;
                  final gutter = wide ? 24.0 : 12.0;
                  final topBar = Padding(
                    padding: EdgeInsets.fromLTRB(
                      gutter,
                      insets.top + 8,
                      gutter,
                      8,
                    ),
                    child: _topBar(),
                  );
                  final editingArea = Column(
                    children: [
                      Expanded(child: _viewerArea()),
                      _transport(gutter),
                      TimelineStrip(
                        controller: _controller,
                        onScrubStart: _stop,
                      ),
                    ],
                  );
                  if (wide) {
                    return Column(
                      children: [
                        topBar,
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    bottom: insets.bottom + 12,
                                  ),
                                  child: editingArea,
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                  0,
                                  0,
                                  gutter,
                                  insets.bottom + 18,
                                ),
                                child: SizedBox(
                                  width: 380,
                                  child: _panelArea(
                                    panelHeight: double.infinity,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }
                  // Each tool gets the height its content needs, like the
                  // photo editor's panels, so the viewer keeps the rest.
                  final preferred = switch (_page) {
                    TimelinePage.edit => 236.0,
                    TimelinePage.color => 300.0,
                    TimelinePage.export => 340.0,
                  };
                  final panelHeight = math.min(
                    preferred,
                    math.max(180.0, constraints.maxHeight * .36),
                  );
                  return Column(
                    children: [
                      topBar,
                      Expanded(child: editingArea),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          gutter,
                          8,
                          gutter,
                          insets.bottom + 10,
                        ),
                        child: _panelArea(panelHeight: panelHeight),
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
    final clips = project.clips.length;
    return GlassNavigationBar(
      leadingKey: const Key('timeline_back'),
      leadingLabel: 'Movies',
      onLeadingPressed: _rendering
          ? null
          : () => Navigator.of(context).maybePop(),
      title: project.name,
      subtitle: clips == 0
          ? 'No clips yet · ${project.aspect.label}'
          : '$clips item${clips == 1 ? '' : 's'} · '
                '${formatTimecode(project.duration, tenths: false)} · '
                '${project.aspect.label}',
      onTitlePressed: _rendering ? null : _rename,
      trailingWidth: 46,
      trailingTint: CupertinoColors.activeBlue,
      trailing: Tooltip(
        message: 'Export movie',
        child: Semantics(
          button: true,
          label: 'Export movie',
          child: CupertinoButton(
            key: const Key('timeline_open_export'),
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            borderRadius: BorderRadius.circular(99),
            color: CupertinoColors.activeBlue,
            disabledColor: CupertinoColors.activeBlue.withValues(alpha: .38),
            onPressed: project.clips.isEmpty
                ? null
                : () => _showPage(TimelinePage.export),
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
              playhead: _controller.playhead,
              playing: _playing,
              onVideoDuration: _controller.setSourceDuration,
            ),
          ),
        ),
        if (empty)
          Positioned.fill(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Start with your best shots',
                    style: TextStyle(
                      color: TimelineColors.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Photos and clips play in the order you add them.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
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
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.add,
                          color: CupertinoColors.white,
                          size: 18,
                        ),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Add photos and clips',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
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

  Widget _transport(double gutter) {
    const tabular = [FontFeature.tabularFigures()];
    final empty = _controller.project.clips.isEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter + 4, 10, gutter, 8),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  text: formatTimecode(_controller.playhead),
                  style: const TextStyle(color: TimelineColors.text),
                  children: [
                    TextSpan(
                      text:
                          ' / ${formatTimecode(_controller.project.duration)}',
                      style: const TextStyle(
                        color: TimelineColors.secondaryText,
                      ),
                    ),
                  ],
                ),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  fontFeatures: tabular,
                ),
              ),
            ),
            GlassIconButton(
              key: const Key('timeline_play'),
              icon: _playing
                  ? CupertinoIcons.pause_fill
                  : CupertinoIcons.play_fill,
              label: _playing ? 'Pause' : 'Play',
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
                    label: 'Undo',
                    size: 40,
                    iconSize: 17,
                    onPressed: _controller.canUndo && !_rendering
                        ? _controller.undo
                        : null,
                  ),
                  const SizedBox(width: 8),
                  GlassIconButton(
                    key: const Key('timeline_redo'),
                    icon: CupertinoIcons.arrow_uturn_right,
                    label: 'Redo',
                    size: 40,
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

  void _showPage(TimelinePage page) => setState(() {
    if (_page == page) {
      _panelOpen = !_panelOpen;
    } else {
      _page = page;
      _panelOpen = true;
    }
  });

  Widget _panelArea({required double panelHeight}) {
    final body = switch (_page) {
      TimelinePage.edit => CutPanel(
        controller: _controller,
        onAdd: _addMedia,
        onMessage: _say,
      ),
      TimelinePage.color => ColorPanel(controller: _controller),
      TimelinePage.export => DeliverPanel(
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
    // An empty movie has nothing to edit yet; the viewer's Add button is
    // the only next step, so the panel stays out of the way.
    final panel = GlassBottomPanel(
      label: '${_page.label} tools',
      open: _panelOpen && _controller.project.clips.isNotEmpty,
      height: panelHeight,
      scrollable: false,
      contentPadding: const EdgeInsets.only(top: 40, bottom: 6),
      onClose: () => setState(() => _panelOpen = false),
      child: body,
    );
    return BackdropGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (panelHeight.isInfinite) Expanded(child: panel) else panel,
          GlassToolRail(
            semanticLabel: 'Movie tools',
            items: [
              for (final page in TimelinePage.values)
                GlassToolRailItem(
                  key: Key('timeline_page_${page.name}'),
                  icon: page.icon,
                  label: page.label,
                ),
            ],
            selectedIndex: _page.index,
            panelOpen: _panelOpen,
            onSelected: (index) => _showPage(TimelinePage.values[index]),
          ),
        ],
      ),
    );
  }
}
