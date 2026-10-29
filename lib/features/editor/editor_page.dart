import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import '../../shared/widgets/app_tooltip.dart';
import '../../shared/widgets/editor_shortcuts.dart';
import '../../shared/widgets/resizable_split.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as p;

import '../../core/app_version.dart';
import '../../core/media/capture_metadata.dart';
import '../../core/media/media_classifier.dart';
import '../../core/media/media_inspection_service.dart';
import '../../core/models/export_options.dart';
import '../../core/models/image_transform_settings.dart';
import '../../core/models/lut_profile.dart';
import '../../core/models/media_edit_state.dart';
import '../../core/models/media_job.dart';
import '../../core/models/media_kind.dart';
import '../../core/models/raw_video_descriptor.dart';
import '../../core/models/restoration_settings.dart';
import '../../core/models/video_edit_settings.dart';
import '../../core/photo/photo_library_service.dart';
import '../../core/persistence/folder_export_service.dart';
import '../../core/persistence/sidecar_service.dart';
import '../../core/platform/raw_processing_service.dart';
import '../../core/platform/share_service.dart';
import '../../core/processing/scene_analyzer.dart';
import '../../core/processing/scene_suggestion_service.dart';
import '../../core/processing/image_restoration_service.dart';
import '../../core/processing/video_restoration_service.dart';
import '../../core/workflow/editor_workflow.dart';
import '../library/export_library_page.dart';
import '../logbook/logbook_page.dart';
import '../../shared/reduce_motion.dart';
import '../../shared/widgets/ocean_backdrop.dart';
import 'edit_history.dart';
import 'editor_tools.dart';
import 'widgets/adjustment_browser.dart';
import 'widgets/app_license_page.dart';
import 'widgets/batch_edit_copy_sheet.dart';
import 'widgets/crop_browser.dart';
import 'widgets/editor_bottom_panel.dart';
import 'widgets/editor_glass_surface.dart';
import 'widgets/editor_preview_stage.dart';
import 'widgets/editor_tool_rail.dart';
import 'widgets/neutral_point_picker.dart';
import 'widgets/preset_browser.dart';
import 'widgets/glass_navigation_bar.dart';
import 'widgets/photo_library_sheet.dart';
import 'widgets/queue_overview_sheet.dart';
import 'widgets/raw_video_dialog.dart';
import 'widgets/setting_slider.dart';
import 'widgets/video_frame_preview_tile.dart';
import '../timeline/movie_from_queue.dart';
import '../timeline/timeline_projects_page.dart';
import '../../shared/widgets/scrollbar_list_view.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/share_failed_dialog.dart';

typedef PhotoMediaPicker = Future<List<String>> Function();

class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    this.initialPaths = const [],
    this.openPhotosOnStart = false,
    this.initialToolGroup,
    this.initialCompareMode,
    this.reviewExportOnStart = false,
    this.libraryOnStart = false,
    this.inspectionService = const MediaInspectionService(),
    this.imageService = const ImageRestorationService(),
    this.photoMediaPicker,
    this.onShowTutorial,
    this.sceneSuggestions,
    this.shareService = const ShareService(),
  });

  final List<String> initialPaths;
  final bool openPhotosOnStart;
  final EditorToolGroup? initialToolGroup;
  final EditorCompareMode? initialCompareMode;
  final bool reviewExportOnStart;
  final bool libraryOnStart;
  final MediaInspectionService inspectionService;
  final ImageRestorationService imageService;
  final PhotoMediaPicker? photoMediaPicker;
  final VoidCallback? onShowTutorial;

  /// Suggests a preset per photo; defaults to the engine-decoder service.
  final SceneSuggestionService? sceneSuggestions;

  /// Opens the system share sheet for finished exports.
  final ShareService shareService;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final ImageRestorationService _imageService = widget.imageService;
  late final SceneSuggestionService _sceneSuggestions =
      widget.sceneSuggestions ?? SceneSuggestionService();
  String? _suggestionPath;
  SceneAnalysis? _suggestion;
  final _videoService = const VideoRestorationService();
  final _rawService = RawProcessingService();
  final _photoLibraryService = const PhotoLibraryService();
  final _folderExportService = const FolderExportService();
  final _sidecarService = const SidecarService();
  final _imagePicker = ImagePicker();
  final _trimStartController = TextEditingController(text: '0');
  final _trimEndController = TextEditingController();
  final Map<String, Duration> _videoPreviewPositions = {};
  final Map<String, Duration> _videoDurations = {};
  final Set<String> _videoPreviewUnavailable = {};

  List<MediaJob> _jobs = const [];
  Map<String, MediaEditState> _editStates = {};
  int _selectedIndex = 0;
  EditorWorkflowStep _step = EditorWorkflowStep.import;
  RawVideoDescriptor _rawDescriptor = RawVideoDescriptor.default4k;
  RestorationSettings _settings = RestorationPreset.auto.settings;
  ImageTransformSettings _transformSettings = const ImageTransformSettings();
  ExportPreset _exportPreset = ExportPreset.archive;
  ExportOptions _exportOptions = ExportPreset.archive.options;
  String? _exportDirectoryPath;
  LutProfile _lutProfile = LutProfile.none;
  bool _trimEnabled = false;
  EditorToolGroup _selectedToolGroup = EditorToolGroup.presets;
  String _selectedAdjustmentId = 'recovery';
  bool _toolPanelOpen = true;
  EditorCompareMode _compareMode = EditorCompareMode.edited;
  EditorCompareMode _exportCompareMode = EditorCompareMode.split;
  EditorPreviewFit _previewFit = EditorPreviewFit.fit;
  bool _busy = false;
  bool _exportStartPending = false;
  bool _cancelRequested = false;
  bool _sharing = false;
  String? _status = 'Ready.';

  /// Local copies written by the last export run, single or batch, which
  /// the status card offers to share.
  List<String> _shareablePaths = const [];

  /// Undo history per queue item, keyed by job id.
  final Map<String, EditHistory<MediaEditState>> _histories = {};

  /// Runs while changes keep coming, so one drag of a wheel or slider
  /// becomes a single undo step.
  Timer? _editStepTimer;
  static const _editStepPause = Duration(milliseconds: 600);

  bool get _exportOperationActive => _busy || _exportStartPending;

  MediaJob? get _selectedJob {
    if (_jobs.isEmpty) return null;
    return _jobs[_selectedIndex.clamp(0, _jobs.length - 1).toInt()];
  }

  MediaEditState get _currentEditState => MediaEditState(
    settings: _settings,
    transform: _transformSettings,
    lutProfile: _lutProfile,
  );

  void _storeSelectedEditState() {
    final job = _selectedJob;
    if (job != null) _editStates[job.id] = _currentEditState;
  }

  void _loadEditStateForIndex(int index) {
    if (index < 0 || index >= _jobs.length) return;
    // A new item never continues the previous item's undo step.
    _endEditStep();
    final state = _editStates.putIfAbsent(
      _jobs[index].id,
      () => const MediaEditState(),
    );
    _settings = state.settings;
    _transformSettings = state.transform;
    _lutProfile = state.lutProfile;
  }

  void _setRestorationSettings(RestorationSettings settings) {
    if (mapEquals(settings.toJson(), _settings.toJson())) return;
    setState(() {
      _recordEditStep();
      _settings = settings;
      _storeSelectedEditState();
    });
  }

  void _setTransformSettings(ImageTransformSettings transform) {
    if (mapEquals(transform.toJson(), _transformSettings.toJson())) return;
    setState(() {
      _recordEditStep();
      _transformSettings = transform;
      _storeSelectedEditState();
    });
  }

  void _setLutProfile(LutProfile profile) {
    if (mapEquals(profile.toJson(), _lutProfile.toJson())) return;
    setState(() {
      _recordEditStep();
      _lutProfile = profile;
      _storeSelectedEditState();
    });
  }

  EditHistory<MediaEditState> _historyFor(String jobId) =>
      _histories.putIfAbsent(jobId, () => EditHistory<MediaEditState>());

  /// Records the state before a change of the selected item. Changes that
  /// follow each other without a pause extend the current undo step.
  void _recordEditStep() {
    final job = _selectedJob;
    if (job == null) return;
    final history = _historyFor(job.id);
    if (_editStepTimer?.isActive ?? false) {
      history.amend();
    } else {
      history.record(_currentEditState);
    }
    _editStepTimer?.cancel();
    _editStepTimer = Timer(_editStepPause, () {});
  }

  void _endEditStep() {
    _editStepTimer?.cancel();
    _editStepTimer = null;
  }

  EditHistory<MediaEditState>? get _selectedHistory {
    final job = _selectedJob;
    return job == null ? null : _histories[job.id];
  }

  bool get _canUndo => !_busy && (_selectedHistory?.canUndo ?? false);

  bool get _canRedo => !_busy && (_selectedHistory?.canRedo ?? false);

  void _undo() => _stepHistory(undo: true);

  void _redo() => _stepHistory(undo: false);

  void _stepHistory({required bool undo}) {
    final history = _selectedHistory;
    if (history == null || _busy) return;
    _endEditStep();
    final current = _currentEditState;
    final state = undo ? history.undo(current) : history.redo(current);
    if (state == null) return;
    setState(() {
      // JPEG quality is an export option that rides along in the settings;
      // undoing an edit must not change it.
      _settings = state.settings.copyWith(jpegQuality: _settings.jpegQuality);
      _transformSettings = state.transform;
      _lutProfile = state.lutProfile;
      _storeSelectedEditState();
    });
  }

  bool get _canCancelCurrentWork {
    if (!_busy ||
        !VideoRestorationService.canCancelRunningJobsOnCurrentPlatform) {
      return false;
    }
    return _jobs.any(
      (job) => job.status == JobStatus.processing && job.kind.isVideo,
    );
  }

  @override
  void initState() {
    super.initState();
    _selectedToolGroup = widget.initialToolGroup ?? EditorToolGroup.presets;
    _compareMode = widget.initialCompareMode ?? EditorCompareMode.edited;
    if (widget.initialPaths.isNotEmpty || widget.openPhotosOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.initialPaths.isNotEmpty) {
          unawaited(_addPaths(widget.initialPaths, MediaSource.photos));
        } else {
          unawaited(_importFromPhotos());
        }
      });
    }
  }

  @override
  void dispose() {
    _editStepTimer?.cancel();
    _trimStartController.dispose();
    _trimEndController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_step == EditorWorkflowStep.export && _selectedJob != null) {
      return _exportOverlayScaffold(_selectedJob!);
    }
    if (_step == EditorWorkflowStep.edit && _selectedJob != null) {
      return CupertinoPageScaffold(
        backgroundColor: CupertinoColors.black,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: _editShortcuts(
            LayoutBuilder(
              builder: (context, constraints) {
                final safeInsets = MediaQuery.paddingOf(context);
                // Landscape phones have no height for a panel under the
                // photo, so they use the side pane too, a little narrower.
                final shortLandscape =
                    constraints.maxWidth > constraints.maxHeight &&
                    constraints.maxHeight < 500 &&
                    constraints.maxWidth >= 560;
                final wide = constraints.maxWidth >= 1040 || shortLandscape;
                if (wide) {
                  final paneWidth = constraints.maxWidth >= 1040
                      ? 390.0
                      : constraints.maxWidth < 700
                      ? 290.0
                      : 330.0;
                  return ResizableSplit(
                    axis: Axis.horizontal,
                    memoryKey: 'photo.sideBySide',
                    defaultExtent: (total) => total - paneWidth,
                    minPreview: _minSidePreviewWidth,
                    minRest: _minSidePaneWidth,
                    // Mostly over the photo: the pane's cards start close
                    // to its edge.
                    handleBias: -.5,
                    builder: (context, extent, rest, resizing) => Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: extent,
                          child: _editStep(
                            wide: true,
                            topInset: safeInsets.top,
                            bottomInset: safeInsets.bottom,
                          ),
                        ),
                        Expanded(
                          // The pane's cards were made for the start
                          // screen's ocean gradient, not the scaffold's
                          // plain black.
                          child: OceanBackdrop(
                            child: SafeArea(left: false, child: _sidePane()),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return _editStep(
                  wide: false,
                  topInset: safeInsets.top,
                  bottomInset: safeInsets.bottom,
                );
              },
            ),
          ),
        ),
      );
    }
    return _importScaffold();
  }

  /// Cmd-Z and Shift-Cmd-Z (Ctrl on other platforms) for the photo
  /// editor's undo history. The editor's own focus scope keeps them working
  /// after a text field gives up focus.
  Widget _editShortcuts(Widget child) {
    return EditorShortcuts(
      canUndo: () => _canUndo,
      onUndo: _undo,
      canRedo: () => _canRedo,
      onRedo: _redo,
      // Escape collapses the tool panel, as it closes a sheet.
      canEscape: () => _toolPanelOpen,
      onEscape: () => setState(() => _toolPanelOpen = false),
      child: child,
    );
  }

  Widget _importScaffold() {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xff041923),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: OceanBackdrop(
          child: SafeArea(
            child: CupertinoTheme(
              data: CupertinoTheme.of(context).copyWith(
                brightness: Brightness.dark,
                primaryColor: CupertinoColors.activeBlue,
                scaffoldBackgroundColor: const Color(0xff041923),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 720;
                  return ScrollbarListView(
                    padding: EdgeInsets.fromLTRB(
                      wide ? 40 : 22,
                      12,
                      wide ? 40 : 22,
                      32,
                    ),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 680),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _importHeader(),
                              SizedBox(height: wide ? 54 : 42),
                              _importStep(),
                              if (_shouldShowStartStatus) ...[
                                const SizedBox(height: 16),
                                _statusPanel(),
                              ],
                            ],
                          ),
                        ),
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

  Widget _importHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The brand needs room next to the icon and the four 44 pt
        // buttons. On narrow phones and with large text, the buttons move to
        // their own row instead of squeezing the name into a sliver.
        const iconAndButtons =
            54 + 13 + 4 * kMinInteractiveDimensionCupertino + 3 * 8;
        final stacked =
            constraints.maxWidth - iconAndButtons <
            MediaQuery.textScalerOf(context).scale(72);
        final brand = Row(
          children: [
            _brandIcon(),
            const SizedBox(width: 13),
            _brandName(),
            if (!stacked) _startShortcuts(),
          ],
        );
        if (!stacked) return brand;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [brand, const SizedBox(height: 14), _startShortcuts()],
        );
      },
    );
  }

  Widget _brandIcon() {
    return Container(
      width: 54,
      height: 54,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CupertinoColors.white.withValues(alpha: .28)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13.5),
        child: Image.asset(
          'assets/branding/aquarecover_app_icon.png',
          key: const Key('start_brand_icon'),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _brandName() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shrinks a little rather than breaking the name on narrow
          // phones next to the four 44 pt buttons.
          const FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'AquaRecover',
              maxLines: 1,
              style: TextStyle(
                color: CupertinoColors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -.3,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Private, on-device restoration',
            style: TextStyle(
              color: CupertinoColors.white.withValues(alpha: .65),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _startShortcuts() {
    Widget shortcut(String key, String label, IconData icon, VoidCallback go) =>
        AppTooltip(
          message: label,
          child: Semantics(
            button: true,
            label: label,
            excludeSemantics: true,
            child: CupertinoButton(
              key: Key(key),
              padding: EdgeInsets.zero,
              minimumSize: const Size(
                kMinInteractiveDimensionCupertino,
                kMinInteractiveDimensionCupertino,
              ),
              borderRadius: BorderRadius.circular(99),
              color: CupertinoColors.white.withValues(alpha: .11),
              onPressed: go,
              child: Icon(icon, color: CupertinoColors.white, size: 20),
            ),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        shortcut('start_movies', 'Movies', CupertinoIcons.film, _openMovies),
        const SizedBox(width: 8),
        shortcut(
          'start_logbook',
          'Dive logbook',
          CupertinoIcons.book,
          _openLogbook,
        ),
        const SizedBox(width: 8),
        shortcut(
          'start_local_exports',
          'Local exports',
          CupertinoIcons.folder,
          _openLocalExports,
        ),
        const SizedBox(width: 8),
        shortcut(
          'start_about',
          'About AquaRecover',
          CupertinoIcons.info,
          _showAbout,
        ),
      ],
    );
  }

  Widget _exportOverlayScaffold(MediaJob job) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final safeInsets = MediaQuery.paddingOf(context);
            final wide = constraints.maxWidth >= 820;
            final horizontalPadding = wide ? 24.0 : 12.0;
            final panel = _exportFloatingPanel(
              wide: wide,
              bottomInset: safeInsets.bottom,
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                EditorPreviewStage(
                  job: job,
                  settings: _settings,
                  compareMode: EditorCompareMode.edited,
                  lutProfile: _lutProfile,
                  immersive: true,
                  showHeader: false,
                  borderRadius: 0,
                  transform: _transformSettings,
                  videoPreviewPosition: _videoPreviewPositions[job.id],
                  onVideoDurationKnown: (duration) =>
                      _setVideoDuration(job.id, duration),
                ),
                Positioned.fill(
                  child: _PhotoScrim(topInset: safeInsets.top, bottom: .54),
                ),
                Positioned(
                  top: safeInsets.top + 8,
                  left: horizontalPadding,
                  right: horizontalPadding,
                  child: _exportTopBar(job),
                ),
                if (wide)
                  Positioned(
                    top: safeInsets.top + 72,
                    right: 24,
                    bottom: safeInsets.bottom + 24,
                    width: 460,
                    child: panel,
                  )
                else
                  Positioned(
                    top: safeInsets.top + 68,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: panel,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _exportFloatingPanel({
    required bool wide,
    required double bottomInset,
  }) {
    final panelRadius = wide
        ? BorderRadius.circular(22)
        : const BorderRadius.vertical(top: Radius.circular(28));
    return ClipRRect(
      borderRadius: panelRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xff141719).withValues(alpha: .96),
            borderRadius: panelRadius,
            border: Border.all(
              color: CupertinoColors.white.withValues(alpha: .18),
            ),
          ),
          child: CupertinoTheme(
            data: CupertinoTheme.of(context).copyWith(
              brightness: Brightness.dark,
              primaryColor: CupertinoColors.activeBlue,
            ),
            child: Builder(
              builder: (panelContext) => ScrollbarListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  wide ? 16 : 20,
                  16,
                  wide ? 18 : bottomInset + 24,
                ),
                children: [_exportStep(panelContext, showActions: false)],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _shouldShowStartStatus {
    if (_busy || _jobs.isNotEmpty) return true;
    final status = _status?.trim();
    if (status == null || status.isEmpty) return false;
    return status != 'Ready.' &&
        status != 'No file selected.' &&
        status != 'No local Photos items were imported.';
  }

  /// The trailing pane at iPad widths. It reuses the start screen's dark
  /// cards and theme, so no light panel sits inside the dark editor.
  /// The wide editor's right column. The tool panel lives here instead of
  /// over the photo, so the preview keeps the window's full height.
  Widget _sidePane() {
    final job = _selectedJob;
    final groups = job == null
        ? const <EditorToolGroup>[]
        : activeEditorToolGroupsFor(job.kind);
    final activeGroup = groups.isEmpty
        ? null
        : groups.contains(_selectedToolGroup)
        ? _selectedToolGroup
        : groups.first;
    return CupertinoTheme(
      data: CupertinoTheme.of(context).copyWith(
        brightness: Brightness.dark,
        primaryColor: CupertinoColors.activeBlue,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => ScrollbarListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
          children: [
            if (activeGroup != null)
              BackdropGroup(
                child: _toolPanelOpen
                    ? EditorBottomPanel(
                        group: activeGroup,
                        open: true,
                        height: math.min(
                          _sidePanelHeight(activeGroup),
                          math.max(200, constraints.maxHeight - 28),
                        ),
                        onClose: () => setState(() => _toolPanelOpen = false),
                        child: _toolPanelContent(activeGroup),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Center(
                          child: EditorCollapsedPanelButton(
                            group: activeGroup,
                            onPressed: () =>
                                setState(() => _toolPanelOpen = true),
                          ),
                        ),
                      ),
              ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _statusPanel(),
                  const SizedBox(height: 12),
                  _queueSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _minPanelHeight = 200.0;

  /// The least the photo keeps beside or above a dragged divider.
  static const _minSidePreviewWidth = 300.0;
  static const _minStackedPreviewHeight = 150.0;
  static const _minSidePaneWidth = 280.0;

  static double _sidePanelHeight(EditorToolGroup group) => switch (group) {
    EditorToolGroup.light => 380.0,
    EditorToolGroup.presets => 420.0,
    EditorToolGroup.crop => 240.0,
    EditorToolGroup.effects => 280.0,
    EditorToolGroup.video => 330.0,
    _ => 300.0,
  };

  Widget _importStep() {
    final job = _selectedJob;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _importHero(job),
        if (_jobs.isNotEmpty) ...[const SizedBox(height: 22), _queueSection()],
      ],
    );
  }

  Widget _importHero(MediaJob? job) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          job == null ? 'Restore underwater color' : 'Add or open media',
          style: CupertinoTheme.of(context).textTheme.navLargeTitleTextStyle
              .copyWith(
                color: CupertinoColors.white,
                fontWeight: FontWeight.w700,
                fontSize: job == null ? 34 : 28,
                letterSpacing: -1,
                height: 1.05,
              ),
        ),
        const SizedBox(height: 13),
        Text(
          job == null
              ? 'Choose one photo or video to edit. Select several to prepare one batch, then export everything with one confirmation.'
              : 'Add more items to the queue or continue with the selected image.',
          style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
            color: CupertinoColors.white.withValues(alpha: .72),
            fontSize: 17,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 28),
        if (_supportsPhotoLibrary || widget.photoMediaPicker != null) ...[
          CupertinoButton(
            key: const Key('start_choose_photos'),
            color: CupertinoColors.white,
            borderRadius: BorderRadius.circular(16),
            onPressed: _busy ? null : _importFromPhotos,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.photo_on_rectangle, size: 20),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Choose from Photos',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        CupertinoButton(
          key: const Key('start_import_files'),
          color: CupertinoColors.white.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(16),
          onPressed: _busy ? null : _pickFiles,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                CupertinoIcons.folder,
                size: 20,
                color: CupertinoColors.white,
              ),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Import Files',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: CupertinoColors.white),
                ),
              ),
            ],
          ),
        ),
        if (_jobs.any((job) => job.kind != MediaKind.rawVideo)) ...[
          const SizedBox(height: 10),
          CupertinoButton(
            key: const Key('start_make_movie'),
            color: CupertinoColors.white.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(16),
            onPressed: _busy ? null : _makeMovieFromQueue,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  CupertinoIcons.film,
                  size: 20,
                  color: CupertinoColors.white,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _jobs.length == 1
                        ? 'Make a movie'
                        : 'Make a movie from ${_jobs.length} items',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: CupertinoColors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (job != null) ...[
          const SizedBox(height: 10),
          CupertinoButton(
            color: CupertinoColors.white.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(16),
            onPressed: _busy
                ? null
                : () => setState(() => _step = EditorWorkflowStep.edit),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    'Edit selected',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: CupertinoColors.white),
                  ),
                ),
                SizedBox(width: 7),
                Icon(
                  CupertinoIcons.chevron_right,
                  color: CupertinoColors.white,
                  size: 17,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _editStep({
    required bool wide,
    double topInset = 0,
    double bottomInset = 0,
  }) {
    final job = _selectedJob;
    if (job == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: _noSelectionState(),
      );
    }
    final groups = activeEditorToolGroupsFor(job.kind);
    final activeGroup = groups.contains(_selectedToolGroup)
        ? _selectedToolGroup
        : groups.first;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final horizontalPadding = wide ? 24.0 : 12.0;
        final bottomPadding = bottomInset + (compact ? 10.0 : 18.0);
        final reservedChrome = compact ? 164.0 : 172.0;
        var reservedPreview = compact ? 250.0 : 320.0;
        double panelRoom() =>
            constraints.maxHeight -
            reservedPreview -
            reservedChrome -
            topInset -
            bottomInset;
        // Short desktop windows (800 × 600, say) give the preview less so
        // the tool panel can still open; without this Open did nothing.
        if (!compact && panelRoom() < _minPanelHeight) {
          reservedPreview = math.max(
            150,
            reservedPreview - (_minPanelHeight - panelRoom()),
          );
        }
        final availablePanelHeight = panelRoom();
        final preferredPanelHeight = compact
            ? switch (activeGroup) {
                EditorToolGroup.light => 332.0,
                EditorToolGroup.presets => 340.0,
                EditorToolGroup.crop => 198.0,
                EditorToolGroup.effects => 240.0,
                EditorToolGroup.video => 290.0,
                _ => 255.0,
              }
            : switch (activeGroup) {
                EditorToolGroup.light => 352.0,
                EditorToolGroup.presets => 360.0,
                EditorToolGroup.crop => 218.0,
                EditorToolGroup.effects => 260.0,
                EditorToolGroup.video => 315.0,
                _ => 275.0,
              };
        final defaultPanelHeight = availablePanelHeight <= 120
            ? 0.0
            : availablePanelHeight.clamp(0.0, preferredPanelHeight).toDouble();
        // Wide windows show the panel in the side pane instead.
        final panelOpen = !wide && _toolPanelOpen && defaultPanelHeight > 0;
        // Under the panel: its margin, the gap above the rail, the rail.
        final belowPanel = bottomPadding + 7 + 2 + GlassToolRail.height;
        final previewTopInset =
            topInset +
            (_jobs.length > 1
                ? (compact ? 128.0 : 132.0)
                : (compact ? 76.0 : 80.0));
        // An open panel trades height with the photo above it.
        return ResizableSplit(
          axis: Axis.vertical,
          memoryKey: 'photo.stacked',
          enabled: panelOpen,
          defaultExtent: (total) => total - belowPanel - defaultPanelHeight,
          minPreview: previewTopInset + _minStackedPreviewHeight,
          minRest: belowPanel + math.min(defaultPanelHeight, _minPanelHeight),
          // Above the panel, clear of its collapse button.
          handleBias: -1,
          gripOffset: -8,
          builder: (context, extent, rest, resizing) {
            final panelHeight = panelOpen
                ? rest - belowPanel
                : defaultPanelHeight;
            return Stack(
              fit: StackFit.expand,
              children: [
                EditorHoldPreview(
                  compareMode: _compareMode,
                  previewBuilder: (mode) => EditorPreviewZoom(
                    resetKey: '${job.id}:${_previewFit.name}',
                    enabled: activeGroup != EditorToolGroup.crop,
                    child: EditorPreviewStage(
                      job: job,
                      settings: _settings,
                      compareMode: mode,
                      lutProfile: _lutProfile,
                      immersive: true,
                      showHeader: false,
                      borderRadius: 0,
                      // While cropping, the frame starts below the floating
                      // buttons so they never cover a corner handle.
                      immersiveTopInset: activeGroup == EditorToolGroup.crop
                          ? previewTopInset +
                                kMinInteractiveDimensionCupertino +
                                12
                          : previewTopInset,
                      immersiveBottomInset:
                          (panelOpen ? panelHeight + 70 : 108) + bottomInset,
                      transform: _transformSettings,
                      showCropGrid: activeGroup == EditorToolGroup.crop,
                      onTransformChanged: activeGroup == EditorToolGroup.crop
                          ? _setTransformSettings
                          : null,
                      previewFit: activeGroup == EditorToolGroup.crop
                          ? EditorPreviewFit.fit
                          : _previewFit,
                      videoPreviewPosition: _videoPreviewPositions[job.id],
                      onVideoDurationKnown: (duration) =>
                          _setVideoDuration(job.id, duration),
                    ),
                  ),
                  // Centred between Undo and Redo on the left and the preview
                  // buttons on the right.
                  heldIndicator: Positioned(
                    top: previewTopInset + 8,
                    left: 0,
                    right: 0,
                    height: kMinInteractiveDimensionCupertino,
                    child: Center(child: _darkPill('Original')),
                  ),
                ),
                Positioned.fill(
                  child: _PhotoScrim(topInset: topInset, bottom: .42),
                ),
                Positioned(
                  top: topInset + 8,
                  left: horizontalPadding,
                  right: horizontalPadding,
                  child: _editorTopBar(job),
                ),
                if (_jobs.length > 1)
                  Positioned(
                    top: topInset + (compact ? 66 : 70),
                    left: horizontalPadding,
                    right: horizontalPadding,
                    child: _editorBatchStrip(job, compact: compact),
                  ),
                Positioned(
                  top: previewTopInset + 8,
                  left: horizontalPadding,
                  child: _undoRedoButtons(),
                ),
                Positioned(
                  top: previewTopInset + 8,
                  right: horizontalPadding,
                  child: Column(
                    children: [
                      _previewCompareButton(
                        mode: _compareMode,
                        onPressed: _toggleComparePreview,
                      ),
                      // Cropping always fits the photo, so the button would
                      // only sit disabled over the crop frame's corner.
                      if (job.kind == MediaKind.photo &&
                          activeGroup != EditorToolGroup.crop) ...[
                        const SizedBox(height: 8),
                        _previewFitButton(fit: _previewFit),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  left: horizontalPadding,
                  right: horizontalPadding,
                  bottom: bottomPadding,
                  child: Center(
                    heightFactor: 1,
                    child: ConstrainedBox(
                      // The rail alone does not need the whole wide window.
                      constraints: BoxConstraints(
                        maxWidth: wide ? 640 : double.infinity,
                      ),
                      child: CupertinoTheme(
                        data: CupertinoTheme.of(context).copyWith(
                          brightness: Brightness.dark,
                          primaryColor: CupertinoColors.activeBlue,
                        ),
                        child: BackdropGroup(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              EditorBottomPanel(
                                group: activeGroup,
                                open: panelOpen,
                                height: panelHeight,
                                onClose: () =>
                                    setState(() => _toolPanelOpen = false),
                                child: _toolPanelContent(activeGroup),
                              ),
                              if (panelOpen) const SizedBox(height: 2),
                              if (!panelOpen && !wide)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: EditorCollapsedPanelButton(
                                    group: activeGroup,
                                    onPressed: () =>
                                        setState(() => _toolPanelOpen = true),
                                  ),
                                ),
                              if (!panelOpen) const SizedBox(height: 2),
                              EditorToolRail(
                                groups: groups,
                                selectedGroup: activeGroup,
                                panelOpen: wide ? _toolPanelOpen : panelOpen,
                                onSelected: _selectToolGroup,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Compact Undo and Redo, matching the movie editor's.
  Widget _undoRedoButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassIconButton(
          key: const Key('editor_undo'),
          icon: CupertinoIcons.arrow_uturn_left,
          label: 'Undo',
          tooltip: withShortcut('Undo', 'Z'),
          iconSize: 17,
          onPressed: _canUndo ? _undo : null,
        ),
        const SizedBox(width: 8),
        GlassIconButton(
          key: const Key('editor_redo'),
          icon: CupertinoIcons.arrow_uturn_right,
          label: 'Redo',
          tooltip: withShortcut('Redo', 'Z', shift: true),
          iconSize: 17,
          onPressed: _canRedo ? _redo : null,
        ),
      ],
    );
  }

  Widget _previewCompareButton({
    required EditorCompareMode mode,
    required VoidCallback onPressed,
    Key buttonKey = const Key('editor_preview_compare'),
  }) {
    final showingSplit = mode.isSplit;
    final actionLabel = showingSplit
        ? 'Show edited preview'
        : 'Show split preview';
    final tint = showingSplit
        ? CupertinoColors.activeBlue.withValues(alpha: .94)
        : const Color(0xff171a20);
    return AppTooltip(
      message: actionLabel,
      child: Semantics(
        button: true,
        selected: showingSplit,
        label: actionLabel,
        child: CupertinoButton(
          key: buttonKey,
          padding: EdgeInsets.zero,
          minimumSize: const Size(
            kMinInteractiveDimensionCupertino,
            kMinInteractiveDimensionCupertino,
          ),
          borderRadius: BorderRadius.circular(99),
          onPressed: onPressed,
          child: EditorGlassSurface(
            style: EditorGlassStyle.clear,
            borderRadius: 99,
            tint: tint,
            child: SizedBox(
              width: 44,
              height: 44,
              child: AnimatedSwitcher(
                duration: motionDuration(
                  context,
                  const Duration(milliseconds: 160),
                ),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  showingSplit
                      ? CupertinoIcons.photo
                      : CupertinoIcons.square_split_2x1,
                  key: ValueKey(showingSplit),
                  color: CupertinoColors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toggleComparePreview() {
    setState(() => _compareMode = _compareMode.toggled);
  }

  void _toggleExportComparePreview() {
    HapticFeedback.selectionClick();
    setState(() => _exportCompareMode = _exportCompareMode.toggled);
  }

  Widget _previewFitButton({required EditorPreviewFit fit}) {
    final actionLabel =
        '${fit.actionLabel}. Pinch with two fingers to inspect details; double-tap to reset zoom.';
    return AppTooltip(
      message: actionLabel,
      child: Semantics(
        button: true,
        selected: fit == EditorPreviewFit.fill,
        label: actionLabel,
        child: CupertinoButton(
          key: const Key('editor_preview_fit'),
          padding: EdgeInsets.zero,
          minimumSize: const Size(
            kMinInteractiveDimensionCupertino,
            kMinInteractiveDimensionCupertino,
          ),
          borderRadius: BorderRadius.circular(99),
          onPressed: () => setState(() => _previewFit = fit.toggled),
          child: EditorGlassSurface(
            style: EditorGlassStyle.clear,
            borderRadius: 99,
            child: SizedBox(
              width: 44,
              height: 44,
              child: AnimatedSwitcher(
                duration: motionDuration(
                  context,
                  const Duration(milliseconds: 160),
                ),
                child: Icon(
                  fit == EditorPreviewFit.fit
                      ? CupertinoIcons.arrow_up_left_arrow_down_right
                      : CupertinoIcons.arrow_down_right_arrow_up_left,
                  key: ValueKey(fit),
                  color: CupertinoColors.white,
                  size: 19,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _editorTopBar(MediaJob job) {
    final title = job.displayName ?? p.basename(job.inputPath);
    return _navigationToolbar(
      leadingLabel: 'Library',
      onLeadingPressed: _busy
          ? null
          : () => setState(() => _step = EditorWorkflowStep.import),
      title: title,
      subtitle: '${_settings.preset.label} - ${job.kind.label}',
      trailingWidth: 46,
      trailing: AppTooltip(
        message: 'Review export',
        child: Semantics(
          button: true,
          label: 'Review export',
          child: CupertinoButton(
            key: const Key('editor_review_export'),
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            borderRadius: BorderRadius.circular(99),
            color: CupertinoColors.activeBlue,
            disabledColor: CupertinoColors.activeBlue.withValues(alpha: .38),
            onPressed: _busy
                ? null
                : () => setState(() => _step = EditorWorkflowStep.export),
            child: Icon(
              CupertinoIcons.share_up,
              color: CupertinoColors.white.withValues(alpha: _busy ? .38 : 1),
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  Widget _exportTopBar(MediaJob job) {
    final videoUnavailable =
        job.kind.isVideo &&
        !VideoRestorationService.isBackendAvailableOnCurrentPlatform;
    final actionLabel = _exportOperationActive
        ? 'Exporting...'
        : _jobs.length > 1
        ? 'Export all'
        : 'Export';
    final exportEnabled = !_exportOperationActive && !videoUnavailable;
    return _navigationToolbar(
      leadingLabel: 'Edit',
      onLeadingPressed: _exportOperationActive
          ? null
          : () => setState(() => _step = EditorWorkflowStep.edit),
      title: 'Export',
      subtitle: _friendlyMediaName(job),
      trailingWidth: _jobs.length > 1 || _exportOperationActive ? 108 : 82,
      trailing: Semantics(
        button: true,
        enabled: exportEnabled,
        label: actionLabel,
        liveRegion: _exportOperationActive,
        child: CupertinoButton(
          key: const Key('export_commit'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          minimumSize: const Size(44, 44),
          borderRadius: BorderRadius.circular(99),
          color: CupertinoColors.activeBlue,
          disabledColor: CupertinoColors.activeBlue.withValues(alpha: .38),
          onPressed: exportEnabled ? _commitExport : null,
          child: AnimatedSwitcher(
            duration: motionDuration(
              context,
              const Duration(milliseconds: 160),
            ),
            child: _exportOperationActive
                ? const Row(
                    key: Key('export_commit_progress'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CupertinoActivityIndicator(
                        radius: 8,
                        color: CupertinoColors.white,
                      ),
                      SizedBox(width: 6),
                      // Large text sizes cut the label short instead of
                      // overflowing the fixed-width bar slot.
                      Flexible(
                        child: Text(
                          'Exporting',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: CupertinoColors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  )
                : Text(
                    actionLabel,
                    key: const Key('export_commit_label'),
                    maxLines: 1,
                    style: TextStyle(
                      color: CupertinoColors.white.withValues(
                        alpha: exportEnabled ? 1 : .62,
                      ),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _navigationToolbar({
    required String leadingLabel,
    required VoidCallback? onLeadingPressed,
    required String title,
    required String subtitle,
    required double trailingWidth,
    required Widget trailing,
  }) {
    return GlassNavigationBar(
      leadingLabel: leadingLabel,
      onLeadingPressed: onLeadingPressed,
      title: title,
      subtitle: subtitle,
      trailingWidth: trailingWidth,
      trailing: trailing,
    );
  }

  Widget _editorBatchStrip(MediaJob job, {required bool compact}) {
    final total = _jobs.length;
    final current = _selectedIndex.clamp(0, total - 1).toInt() + 1;
    final failed = _jobs
        .where((item) => item.status == JobStatus.failed)
        .length;
    final processing = _jobs
        .where((item) => item.status == JobStatus.processing)
        .length;
    final pending = total - failed - processing;
    return _floatingGlass(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      borderRadius: 20,
      child: Row(
        children: [
          _editorIconButton(
            key: const Key('editor_previous_item'),
            icon: CupertinoIcons.chevron_back,
            tooltip: 'Previous item',
            onPressed: _busy || _selectedIndex <= 0
                ? null
                : () => _selectJobIndex(_selectedIndex - 1),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: CupertinoButton(
              key: const Key('editor_open_queue'),
              padding: EdgeInsets.zero,
              minimumSize: const Size(
                kMinInteractiveDimensionCupertino,
                kMinInteractiveDimensionCupertino,
              ),
              alignment: Alignment.centerLeft,
              onPressed: _showQueueOverview,
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.rectangle_stack,
                    color: CupertinoColors.white,
                    size: 19,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          compact
                              ? 'Selection $current/$total'
                              : '$current of $total - ${job.displayName ?? p.basename(job.inputPath)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CupertinoTheme.of(context).textTheme.textStyle
                              .copyWith(
                                color: CupertinoColors.white,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$pending ready${processing == 0 ? '' : ' - $processing processing'}${failed == 0 ? '' : ' - $failed failed'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CupertinoTheme.of(context).textTheme.textStyle
                              .copyWith(
                                color: CupertinoColors.white.withValues(
                                  alpha: .72,
                                ),
                                fontSize: 12,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          _editorIconButton(
            key: const Key('editor_copy_edits'),
            icon: CupertinoIcons.doc_on_doc,
            tooltip: 'Copy this photo’s edits',
            onPressed: _busy || !_canCopyEditsFrom(job)
                ? null
                : _showBatchEditCopySheet,
          ),
          const SizedBox(width: 6),
          _editorIconButton(
            key: const Key('editor_next_item'),
            icon: CupertinoIcons.chevron_forward,
            tooltip: 'Next item',
            onPressed: _busy || _selectedIndex >= total - 1
                ? null
                : () => _selectJobIndex(_selectedIndex + 1),
          ),
        ],
      ),
    );
  }

  Widget _editorIconButton({
    Key? key,
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
  }) {
    final button = CupertinoButton(
      key: key,
      padding: EdgeInsets.zero,
      minimumSize: const Size(
        kMinInteractiveDimensionCupertino,
        kMinInteractiveDimensionCupertino,
      ),
      borderRadius: BorderRadius.circular(99),
      onPressed: onPressed,
      child: Icon(
        icon,
        color: CupertinoColors.white.withValues(
          alpha: onPressed == null ? .34 : 1,
        ),
        size: 17,
      ),
    );
    return AppTooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: tooltip,
        excludeSemantics: true,
        child: button,
      ),
    );
  }

  bool _canCopyEditsFrom(MediaJob source) {
    return source.kind.isImage &&
        _jobs.any((job) => job.id != source.id && job.kind.isImage);
  }

  Future<void> _showBatchEditCopySheet() {
    final source = _selectedJob;
    if (source == null || !_canCopyEditsFrom(source) || _busy) {
      return Future.value();
    }
    _storeSelectedEditState();
    final targets = [
      for (final job in _jobs)
        if (job.id != source.id && job.kind.isImage)
          job.copyWith(displayName: _friendlyMediaName(job)),
    ];
    return showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => BatchEditCopySheet(
        source: source.copyWith(displayName: _friendlyMediaName(source)),
        targets: targets,
        onApplySelected: (ids) =>
            _applyEditsToTargets(sourceId: source.id, targetIds: ids),
        onApplyAll: () => _confirmAndApplyEditsToAll(
          sourceId: source.id,
          targetIds: targets.map((job) => job.id).toSet(),
        ),
      ),
    );
  }

  Future<bool> _applyEditsToTargets({
    required String sourceId,
    required Set<String> targetIds,
  }) async {
    if (!mounted || targetIds.isEmpty || !_editStates.containsKey(sourceId)) {
      return false;
    }
    setState(() {
      // Each photo that receives the edits can undo them on its own.
      for (final id in targetIds) {
        final previous = _editStates[id];
        if (previous != null) _historyFor(id).record(previous);
      }
      _editStates = copyMediaEditStateToTargets(
        states: _editStates,
        sourceId: sourceId,
        targetIds: targetIds,
      );
      _status =
          'Copied edits to ${targetIds.length} photo${targetIds.length == 1 ? '' : 's'}.';
    });
    return true;
  }

  Future<bool> _confirmAndApplyEditsToAll({
    required String sourceId,
    required Set<String> targetIds,
  }) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Apply edits to all photos?'),
        content: const Text(
          'This photo’s edits will be applied to all other photos in the queue.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            key: const Key('confirm_apply_edits_to_all'),
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    return _applyEditsToTargets(sourceId: sourceId, targetIds: targetIds);
  }

  void _selectToolGroup(EditorToolGroup group) {
    setState(() {
      if (_selectedToolGroup == group) {
        _toolPanelOpen = !_toolPanelOpen;
      } else {
        _selectedToolGroup = group;
        _toolPanelOpen = true;
      }
    });
  }

  Widget _toolPanelContent(EditorToolGroup group) {
    return Builder(
      builder: (panelContext) => switch (group) {
        EditorToolGroup.presets => PresetBrowser(
          settings: _settings,
          enabled: !_busy,
          suggestion: _suggestionFor(_selectedJob),
          onChanged: _setRestorationSettings,
        ),
        EditorToolGroup.light => AdjustmentBrowser(
          controls: allImageAdjustmentControls,
          settings: _settings,
          presetSettings: _settings.presetBaseline,
          selectedId: _selectedAdjustmentId,
          enabled: !_busy,
          trailing: _selectedJob?.kind == MediaKind.photo
              ? CupertinoButton(
                  key: const Key('open_neutral_picker'),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(
                    kMinInteractiveDimensionCupertino,
                    kMinInteractiveDimensionCupertino,
                  ),
                  onPressed: _busy ? null : _pickNeutralPoint,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.eyedropper, size: 16),
                      SizedBox(width: 4),
                      // Wraps instead of overflowing at the largest sizes.
                      Flexible(
                        child: Text(
                          'White balance',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )
              : null,
          onSelected: (id) => setState(() => _selectedAdjustmentId = id),
          onChanged: _setRestorationSettings,
        ),
        EditorToolGroup.crop => CropBrowser(
          settings: _transformSettings,
          sourceAspectRatio: _previewAspectRatio(_selectedJob!),
          enabled: !_busy,
          onChanged: _setTransformSettings,
        ),
        EditorToolGroup.effects => _lutSection(panelContext),
        EditorToolGroup.color || EditorToolGroup.details => _adjustmentSliders(
          panelContext,
          group.adjustments,
        ),
        EditorToolGroup.video => _videoSection(panelContext),
      },
    );
  }

  Widget _adjustmentSliders(
    BuildContext panelContext,
    List<AdjustmentControl> controls,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Manual adjustments', style: _panelTitle(panelContext)),
        const SizedBox(height: 6),
        for (final control in controls)
          SettingSlider(
            label: control.label,
            value: control.value(_settings),
            min: control.min,
            max: control.max,
            divisions: control.divisions,
            help: control.help,
            format: control.format,
            onChanged: _busy
                ? null
                : (value) =>
                      _setRestorationSettings(control.apply(_settings, value)),
          ),
      ],
    );
  }

  Widget _exportStep(BuildContext panelContext, {bool showActions = true}) {
    final job = _selectedJob;
    if (job == null) return _noSelectionState();
    final videoUnavailable =
        job.kind.isVideo &&
        !VideoRestorationService.isBackendAvailableOnCurrentPlatform;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _selectedMediaHeader(panelContext, job),
        const SizedBox(height: 16),
        Text(
          'Preview',
          style: CupertinoTheme.of(panelContext).textTheme.navTitleTextStyle,
        ),
        const SizedBox(height: 8),
        _exportPreview(job),
        const SizedBox(height: 14),
        if (_jobs.length > 1) ...[
          _batchExportReviewPanel(panelContext),
          const SizedBox(height: 12),
        ],
        if (_canShareExports) ...[
          _shareExportsButton(),
          const SizedBox(height: 12),
        ],
        _exportOptionsSection(panelContext),
        if (videoUnavailable) ...[
          const SizedBox(height: 12),
          _noticePanel('Video export unavailable', _videoUnavailableMessage),
        ],
        if (showActions) const SizedBox(height: 12),
        if (showActions)
          Row(
            children: [
              Expanded(
                child: CupertinoButton(
                  onPressed: _exportOperationActive
                      ? null
                      : () => setState(() => _step = EditorWorkflowStep.edit),
                  child: const Text('Back to edit'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CupertinoButton.filled(
                  onPressed: (_exportOperationActive || videoUnavailable)
                      ? null
                      : _commitExport,
                  child: Text(
                    _exportOperationActive
                        ? 'Exporting...'
                        : _jobs.length > 1
                        ? 'Export all'
                        : 'Export',
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _emptyImportState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: CupertinoDynamicColor.resolve(
            CupertinoColors.separator,
            context,
          ),
        ),
      ),
      child: Column(
        children: [
          const Icon(
            CupertinoIcons.photo_on_rectangle,
            size: 54,
            color: CupertinoColors.white,
          ),
          const SizedBox(height: 10),
          Text(
            'No media selected',
            style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
          ),
          const SizedBox(height: 6),
          Text(
            'Choose a local photo or video to begin.',
            style: _secondaryText(context),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _noSelectionState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _emptyImportState(),
        const SizedBox(height: 16),
        CupertinoButton.filled(
          onPressed: _busy
              ? null
              : () => setState(() => _step = EditorWorkflowStep.import),
          child: const Text('Go to import'),
        ),
      ],
    );
  }

  String _friendlyMediaName(MediaJob job) {
    final rawName = job.displayName ?? p.basename(job.inputPath);
    final uuidLike = RegExp(
      r'^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}',
    ).hasMatch(rawName);
    final tempPhotosName =
        job.source == MediaSource.photos &&
        (uuidLike || rawName.length > 42 || rawName.contains('_L0_'));
    if (tempPhotosName) {
      return job.kind == MediaKind.video ? 'Imported video' : 'Imported photo';
    }
    return rawName;
  }

  String _mediaSummary(MediaJob job) {
    final details = <String>[
      job.kind.label,
      job.source.label,
      job.status.label,
      if (job.metadata?.sizeLabel != null) job.metadata!.sizeLabel,
      if (job.metadata?.dimensionsLabel != null) job.metadata!.dimensionsLabel!,
      if (_lutProfile.isEnabled) 'LUT ${_lutProfile.name}',
    ];
    return details.join(' - ');
  }

  Widget _selectedMediaHeader(BuildContext panelContext, MediaJob job) {
    final title = _friendlyMediaName(job);
    final subtitle = _mediaSummary(job);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CupertinoColors.white.withValues(alpha: .14)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: CupertinoColors.activeBlue.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              job.kind.isVideo ? CupertinoIcons.film : CupertinoIcons.photo,
              color: CupertinoColors.white,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CupertinoTheme.of(
                    panelContext,
                  ).textTheme.textStyle.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: CupertinoTheme.of(panelContext).textTheme.textStyle
                      .copyWith(
                        color: CupertinoColors.systemGrey,
                        fontSize: 12,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _darkPill(job.status.label),
        ],
      ),
    );
  }

  Widget _exportPreview(MediaJob job) {
    final sourceAspectRatio = _previewAspectRatio(job);
    return AspectRatio(
      aspectRatio: _transformSettings.outputAspectRatio(sourceAspectRatio),
      child: Stack(
        fit: StackFit.expand,
        children: [
          EditorHoldPreview(
            key: const Key('export_preview_hold'),
            compareMode: _exportCompareMode,
            previewBuilder: (mode) => EditorPreviewStage(
              key: const Key('export_preview_stage'),
              job: job,
              settings: _settings,
              compareMode: mode,
              lutProfile: _lutProfile,
              showHeader: false,
              borderRadius: 16,
              transform: _transformSettings,
              previewFit: EditorPreviewFit.fill,
              videoPreviewPosition: _videoPreviewPositions[job.id],
              onVideoDurationKnown: (duration) =>
                  _setVideoDuration(job.id, duration),
            ),
            heldIndicator: Positioned(
              left: 10,
              top: 10,
              child: _darkPill('Original'),
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: _previewCompareButton(
              buttonKey: const Key('export_preview_compare'),
              mode: _exportCompareMode,
              onPressed: _toggleExportComparePreview,
            ),
          ),
        ],
      ),
    );
  }

  List<String> _exportDestinationNames() => [
    if (_exportOptions.keepLocalCopy) 'AquaRecover',
    if (_exportOptions.saveToPhotoLibrary) 'Photos',
    if (_exportOptions.saveToFiles) 'Files',
  ];

  Widget _batchExportReviewPanel(BuildContext panelContext) {
    final failed = _jobs.where((job) => job.status == JobStatus.failed).length;
    final processing = _jobs
        .where((job) => job.status == JobStatus.processing)
        .length;
    final pending = _jobs.length - failed - processing;
    final selected = _selectedJob;
    final videoUnavailable =
        selected != null &&
        selected.kind.isVideo &&
        !VideoRestorationService.isBackendAvailableOnCurrentPlatform;
    final canExportSelected =
        selected != null &&
        !_exportOperationActive &&
        !videoUnavailable &&
        selected.status.canStartIndividualExport;
    final actionLabel = switch (selected?.status) {
      JobStatus.failed => 'Retry selected',
      JobStatus.processing => 'Exporting selected...',
      JobStatus.complete => 'Exported',
      _ => 'Export selected',
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CupertinoColors.white.withValues(alpha: .13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(CupertinoIcons.rectangle_stack, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Batch export',
                      style: CupertinoTheme.of(
                        panelContext,
                      ).textTheme.navTitleTextStyle,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$pending ready${processing == 0 ? '' : ' - $processing processing'}${failed == 0 ? '' : ' - $failed failed'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CupertinoTheme.of(panelContext).textTheme.textStyle
                          .copyWith(
                            color: CupertinoColors.systemGrey,
                            fontSize: 12,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CupertinoButton(
                key: const Key('export_open_queue'),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(
                  kMinInteractiveDimensionCupertino,
                  kMinInteractiveDimensionCupertino,
                ),
                // White, not the tint: blue text on the card stays below
                // 4.5:1.
                foregroundColor: _exportOperationActive
                    ? null
                    : CupertinoColors.white,
                onPressed: _exportOperationActive ? null : _showQueueOverview,
                child: const Text('Manage'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: BoxDecoration(
              color: CupertinoColors.white.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: CupertinoColors.white.withValues(alpha: .08),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Selected item',
                        style: TextStyle(
                          color: CupertinoColors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        selected == null
                            ? 'No item selected'
                            : _friendlyMediaName(selected),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CupertinoTheme.of(panelContext)
                            .textTheme
                            .textStyle
                            .copyWith(
                              color: CupertinoColors.systemGrey,
                              fontSize: 12,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                CupertinoButton(
                  key: const Key('export_selected_batch'),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(
                    kMinInteractiveDimensionCupertino,
                    kMinInteractiveDimensionCupertino,
                  ),
                  borderRadius: BorderRadius.circular(11),
                  color: CupertinoColors.white.withValues(alpha: .10),
                  foregroundColor: canExportSelected
                      ? CupertinoColors.white
                      : null,
                  onPressed: canExportSelected ? _commitSelectedExport : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(CupertinoIcons.arrow_up_square, size: 17),
                      const SizedBox(width: 6),
                      Text(actionLabel),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _noticePanel(String title, String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
          CupertinoColors.secondarySystemGroupedBackground,
          context,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CupertinoDynamicColor.resolve(
            CupertinoColors.separator,
            context,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: CupertinoTheme.of(
              context,
            ).textTheme.textStyle.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(message, style: _secondaryText(context)),
        ],
      ),
    );
  }

  Widget _videoSection(BuildContext panelContext) {
    final job = _selectedJob;
    final duration = job == null ? null : _videoDurations[job.id];
    final position = job == null ? null : _videoPreviewPositions[job.id];
    final previewEnd = duration == null
        ? null
        : VideoFramePreviewTile.clampPosition(duration, duration);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose the frame used in the editor and export preview. This does not change the exported video timeline.',
          style: _secondaryText(panelContext),
        ),
        if (job?.kind == MediaKind.video && duration != null) ...[
          SettingSlider(
            key: const Key('video_preview_frame'),
            label: 'Preview frame',
            value: (position ?? Duration.zero).inMilliseconds / 1000,
            min: 0,
            max: (previewEnd!.inMilliseconds / 1000)
                .clamp(.05, double.infinity)
                .toDouble(),
            divisions: (previewEnd.inMilliseconds / 250)
                .round()
                .clamp(1, 400)
                .toInt(),
            format: (value) => _formatVideoPosition(
              Duration(milliseconds: (value * 1000).round()),
            ),
            onChanged: _busy
                ? null
                : (value) => _setVideoPreviewPosition(
                    job!.id,
                    Duration(milliseconds: (value * 1000).round()),
                  ),
          ),
        ] else if (job?.kind == MediaKind.video &&
            _videoPreviewUnavailable.contains(job!.id)) ...[
          const SizedBox(height: 10),
          Text(
            'Frame preview is not available for this video on this device.',
            key: const Key('video_preview_unavailable'),
            style: _secondaryText(panelContext),
          ),
          const SizedBox(height: 8),
        ] else if (job?.kind == MediaKind.video) ...[
          const SizedBox(height: 10),
          const Row(
            children: [
              CupertinoActivityIndicator(),
              SizedBox(width: 9),
              Flexible(child: Text('Preparing video timeline…')),
            ],
          ),
          const SizedBox(height: 8),
        ] else
          const SizedBox(height: 8),
        _switchRow(
          title: 'Trim video',
          value: _trimEnabled,
          onChanged: (v) => setState(() => _trimEnabled = v),
          styleContext: panelContext,
        ),
        Row(
          children: [
            Expanded(
              child: _numberField(
                label: 'Start seconds',
                controller: _trimStartController,
                enabled: _trimEnabled,
                styleContext: panelContext,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _numberField(
                label: 'End seconds',
                controller: _trimEndController,
                enabled: _trimEnabled,
                placeholder: 'Optional',
                styleContext: panelContext,
              ),
            ),
          ],
        ),
        if (job?.kind == MediaKind.rawVideo) ...[
          const SizedBox(height: 8),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _busy
                ? null
                : () async {
                    final descriptor = await RawVideoDialog.show(
                      context,
                      initial: _rawDescriptor,
                    );
                    if (descriptor != null && mounted) {
                      setState(() => _rawDescriptor = descriptor);
                    }
                  },
            child: Text(
              'RAW video: ${_rawDescriptor.width}x${_rawDescriptor.height} ${_rawDescriptor.frameRate.toStringAsFixed(2)}fps ${_rawDescriptor.pixelFormat}',
            ),
          ),
        ],
      ],
    );
  }

  void _setVideoDuration(String jobId, Duration duration) {
    if (!mounted) return;
    if (duration <= Duration.zero) {
      // The frame preview cannot open this video on this device.
      if (_videoPreviewUnavailable.add(jobId)) setState(() {});
      return;
    }
    final existingDuration = _videoDurations[jobId];
    final existingPosition = _videoPreviewPositions[jobId];
    final nextPosition = VideoFramePreviewTile.clampPosition(
      existingPosition ??
          VideoFramePreviewTile.representativePositionFor(duration),
      duration,
    );
    if (existingDuration == duration && existingPosition == nextPosition) {
      return;
    }
    setState(() {
      _videoDurations[jobId] = duration;
      _videoPreviewPositions[jobId] = nextPosition;
    });
  }

  void _setVideoPreviewPosition(String jobId, Duration position) {
    final duration = _videoDurations[jobId];
    if (duration == null) return;
    setState(() {
      _videoPreviewPositions[jobId] = VideoFramePreviewTile.clampPosition(
        position,
        duration,
      );
    });
  }

  String _formatVideoPosition(Duration position) {
    final totalSeconds = position.inMilliseconds / 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds - minutes * 60;
    return '$minutes:${seconds.toStringAsFixed(1).padLeft(4, '0')}';
  }

  Widget _lutSection(BuildContext panelContext) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The pills' 44 pt hit regions already keep the rows apart.
        Wrap(
          spacing: 8,
          children: [
            for (final profile in LutProfile.builtIns)
              _choicePill(
                label: profile.name,
                selected: _lutProfile.kind == profile.kind,
                styleContext: panelContext,
                onPressed: _busy
                    ? null
                    : () => _setLutProfile(
                        profile.copyWith(
                          intensity: profile.kind == LutKind.none ? 0 : 1,
                        ),
                      ),
              ),
            if (_lutProfile.isCustomCube)
              _choicePill(
                label: p.basename(_lutProfile.path!),
                selected: true,
                onPressed: null,
                styleContext: panelContext,
              ),
          ],
        ),
        const SizedBox(height: 8),
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _busy ? null : _importCubeLut,
          child: const Text('Import .cube LUT'),
        ),
        SettingSlider(
          label: 'LUT intensity',
          value: _lutProfile.intensity.clamp(0.0, 1.0).toDouble(),
          min: 0,
          max: 1,
          divisions: 20,
          onChanged: _busy
              ? null
              : (v) => _setLutProfile(_lutProfile.copyWith(intensity: v)),
        ),
      ],
    );
  }

  Widget _exportOptionsSection(BuildContext panelContext) {
    final isVideo = _selectedJob?.kind.isVideo ?? false;
    // Explicit label colors override the segmented controls' own disabled
    // style, so the labels and thumb dim themselves during an export.
    final segmentLabel = TextStyle(
      color: CupertinoColors.white.withValues(
        alpha: _exportOperationActive ? .38 : 1,
      ),
    );
    final segmentThumb = CupertinoColors.activeBlue.withValues(
      alpha: _exportOperationActive ? .38 : 1,
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CupertinoColors.white.withValues(alpha: .13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Export settings',
            style: CupertinoTheme.of(panelContext).textTheme.navTitleTextStyle,
          ),
          const SizedBox(height: 3),
          Text(
            'Format, quality, and destination',
            style: CupertinoTheme.of(panelContext).textTheme.textStyle.copyWith(
              color: CupertinoColors.systemGrey,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          CupertinoSlidingSegmentedControl<ExportPreset>(
            groupValue: _exportPreset,
            backgroundColor: CupertinoColors.white.withValues(alpha: .10),
            thumbColor: segmentThumb,
            disabledChildren: _exportOperationActive
                ? ExportPreset.values.toSet()
                : const {},
            children: {
              for (final preset in ExportPreset.values)
                preset: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(preset.label, style: segmentLabel),
                ),
            },
            onValueChanged: (value) {
              if (value != null && !_exportOperationActive) {
                _applyExportPreset(value);
              }
            },
          ),
          const SizedBox(height: 8),
          if (isVideo)
            CupertinoSlidingSegmentedControl<VideoOutputFormat>(
              key: const Key('video_output_format'),
              groupValue: _exportOptions.videoFormat,
              backgroundColor: CupertinoColors.white.withValues(alpha: .10),
              thumbColor: segmentThumb,
              disabledChildren: _exportOperationActive
                  ? VideoOutputFormat.values.toSet()
                  : const {},
              children: {
                for (final format in VideoOutputFormat.values)
                  format: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(format.label, style: segmentLabel),
                  ),
              },
              onValueChanged: (value) {
                if (value != null && !_exportOperationActive) {
                  setState(() {
                    _exportPreset = ExportPreset.proEdit;
                    _exportOptions = _exportOptions.copyWith(
                      videoFormat: value,
                    );
                  });
                }
              },
            )
          else
            CupertinoSlidingSegmentedControl<ImageOutputFormat>(
              key: const Key('image_output_format'),
              groupValue: _exportOptions.imageFormat,
              backgroundColor: CupertinoColors.white.withValues(alpha: .10),
              thumbColor: segmentThumb,
              disabledChildren: _exportOperationActive
                  ? ImageOutputFormat.values.toSet()
                  : const {},
              children: {
                ImageOutputFormat.jpeg: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('JPEG', style: segmentLabel),
                ),
                ImageOutputFormat.png: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('PNG', style: segmentLabel),
                ),
              },
              onValueChanged: (value) {
                if (value != null && !_exportOperationActive) {
                  setState(() {
                    _exportPreset = ExportPreset.proEdit;
                    _exportOptions = _exportOptions.copyWith(
                      imageFormat: value,
                    );
                  });
                }
              },
            ),
          const SizedBox(height: 8),
          _switchRow(
            title: 'Keep in AquaRecover',
            controlKey: const Key('export_keep_local_copy'),
            value: _exportOptions.keepLocalCopy,
            styleContext: panelContext,
            onChanged: _setKeepLocalCopy,
          ),
          if (_supportsPhotoLibrary)
            _switchRow(
              title: 'Add to Photos',
              controlKey: const Key('export_add_to_photos'),
              value: _exportOptions.saveToPhotoLibrary,
              styleContext: panelContext,
              onChanged: _setSaveToPhotoLibrary,
            ),
          _switchRow(
            title: 'Export to Files',
            controlKey: const Key('export_to_files'),
            value: _exportOptions.saveToFiles,
            styleContext: panelContext,
            onChanged: (value) => unawaited(_setSaveToFiles(value)),
          ),
          if (_exportOptions.saveToFiles && _exportDirectoryPath != null) ...[
            Container(
              key: const Key('export_files_folder'),
              padding: const EdgeInsets.fromLTRB(11, 8, 8, 8),
              decoration: BoxDecoration(
                color: CupertinoColors.white.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.folder_fill,
                    color: CupertinoColors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.basename(_exportDirectoryPath!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: CupertinoColors.white),
                    ),
                  ),
                  CupertinoButton(
                    key: const Key('change_export_files_folder'),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(
                      kMinInteractiveDimensionCupertino,
                      kMinInteractiveDimensionCupertino,
                    ),
                    foregroundColor: _exportOperationActive
                        ? null
                        : CupertinoColors.white,
                    onPressed: _exportOperationActive
                        ? null
                        : () => unawaited(_chooseExportDirectory()),
                    child: const Text('Change'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],
          const SizedBox(height: 2),
          Text(
            _supportsPhotoLibrary
                ? 'Choose one or more destinations. Photos and Files exports do not appear under Local Exports unless a local copy is enabled.'
                : 'Choose one or more destinations. Files exports do not appear under Local Exports unless a local copy is enabled.',
            style: CupertinoTheme.of(panelContext).textTheme.textStyle.copyWith(
              color: CupertinoColors.systemGrey,
              fontSize: 12,
            ),
          ),
          if (!isVideo && _exportOptions.imageFormat == ImageOutputFormat.jpeg)
            SettingSlider(
              key: const Key('jpeg_quality'),
              label: 'JPEG quality',
              value: _settings.jpegQuality.toDouble(),
              min: 70,
              max: 100,
              divisions: 30,
              format: (v) => v.round().toString(),
              onChanged: _exportOperationActive
                  ? null
                  : (v) => _setJpegQuality(v.round()),
            ),
          if (_jobs.any((job) => !job.kind.isVideo))
            ..._beforeAfterOptions(segmentLabel, segmentThumb, panelContext),
          _switchRow(
            title: 'Strip metadata',
            value: _exportOptions.stripMetadata,
            styleContext: panelContext,
            onChanged: (v) => setState(
              () => _exportOptions = _exportOptions.copyWith(stripMetadata: v),
            ),
          ),
          if (isVideo)
            _switchRow(
              title: 'Keep video audio',
              value: _exportOptions.keepAudio,
              styleContext: panelContext,
              onChanged: (v) => setState(
                () => _exportOptions = _exportOptions.copyWith(keepAudio: v),
              ),
            ),
        ],
      ),
    );
  }

  /// The before/after comparison controls. They apply to every photo in
  /// the export, including each photo of a batch; videos ignore them.
  List<Widget> _beforeAfterOptions(
    TextStyle segmentLabel,
    Color segmentThumb,
    BuildContext panelContext,
  ) {
    final options = _exportOptions;
    return [
      _switchRow(
        title: 'Before/After image',
        controlKey: const Key('export_before_after'),
        tooltip:
            'Export each photo as one image showing the original and the restored version',
        value: options.beforeAfter,
        styleContext: panelContext,
        onChanged: (v) => setState(
          () => _exportOptions = _exportOptions.copyWith(beforeAfter: v),
        ),
      ),
      if (options.beforeAfter) ...[
        AppTooltip(
          message: options.beforeAfterLayout == BeforeAfterLayout.split
              ? 'Split: original on the left half, restored on the right'
              : 'Side by side: landscape photos are stacked, portrait photos sit next to each other',
          child: CupertinoSlidingSegmentedControl<BeforeAfterLayout>(
            key: const Key('export_before_after_layout'),
            groupValue: options.beforeAfterLayout,
            backgroundColor: CupertinoColors.white.withValues(alpha: .10),
            thumbColor: segmentThumb,
            disabledChildren: _exportOperationActive
                ? BeforeAfterLayout.values.toSet()
                : const {},
            children: {
              for (final layout in BeforeAfterLayout.values)
                layout: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(layout.label, style: segmentLabel),
                ),
            },
            onValueChanged: (value) {
              if (value != null && !_exportOperationActive) {
                setState(
                  () => _exportOptions = _exportOptions.copyWith(
                    beforeAfterLayout: value,
                  ),
                );
              }
            },
          ),
        ),
        _switchRow(
          title: 'Before and After labels',
          controlKey: const Key('export_before_after_labels'),
          tooltip: 'Show small Before and After labels on the image',
          value: options.beforeAfterLabels,
          styleContext: panelContext,
          onChanged: (v) => setState(
            () =>
                _exportOptions = _exportOptions.copyWith(beforeAfterLabels: v),
          ),
        ),
      ],
    ];
  }

  /// The queue card on the start screen and in the editor's iPad side pane.
  /// Both sit on dark backgrounds, so the card uses the dark style.
  Widget _queueSection() {
    const titleStyle = TextStyle(
      color: CupertinoColors.white,
      fontSize: 20,
      fontWeight: FontWeight.w700,
    );
    final subtitleStyle = TextStyle(
      color: CupertinoColors.white.withValues(alpha: .78),
      fontSize: 12,
    );
    return Container(
      key: const Key('start_queue'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CupertinoColors.white.withValues(alpha: .13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Queue', style: titleStyle),
                    const SizedBox(height: 3),
                    Text(
                      '${_jobs.length} item${_jobs.length == 1 ? '' : 's'} selected',
                      style: subtitleStyle,
                    ),
                  ],
                ),
              ),
              if (_jobs.isNotEmpty)
                CupertinoButton(
                  key: const Key('start_open_queue'),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(
                    kMinInteractiveDimensionCupertino,
                    kMinInteractiveDimensionCupertino,
                  ),
                  // White, not the tint: blue text on this card stays
                  // below 4.5:1 over the ocean gradient.
                  foregroundColor: _busy ? null : CupertinoColors.white,
                  onPressed: _busy ? null : _showQueueOverview,
                  child: const Text('Manage'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_jobs.isEmpty)
            Text('No media imported.', style: subtitleStyle)
          else
            Column(
              children: [
                for (var i = 0; i < _jobs.length; i++) _queueRow(i, _jobs[i]),
              ],
            ),
        ],
      ),
    );
  }

  Widget _queueRow(int index, MediaJob job) {
    final selected = index == _selectedIndex;
    final primary = CupertinoTheme.of(context).primaryColor;
    final details = <String>[
      job.kind.label,
      job.source.label,
      job.status.label,
      if (job.metadata?.sizeLabel != null) job.metadata!.sizeLabel,
      if (job.metadata?.dimensionsLabel != null) job.metadata!.dimensionsLabel!,
      if (job.metadata?.durationLabel != null) job.metadata!.durationLabel!,
    ];
    final canRemove =
        (!_busy || job.status == JobStatus.pending) &&
        job.status != JobStatus.processing;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Edit ${_friendlyMediaName(job)}',
      child: GestureDetector(
        key: Key('start_queue_item_${job.id}'),
        onTap: _busy
            ? null
            : () => _selectJobIndex(
                index,
                openEditor: _step == EditorWorkflowStep.import,
              ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected
                ? primary.withValues(alpha: .18)
                : CupertinoColors.white.withValues(alpha: .055),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? primary.withValues(alpha: 0.42)
                  : CupertinoColors.white.withValues(alpha: .10),
            ),
          ),
          child: Row(
            children: [
              _queueInlineThumbnail(job),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A pane dragged narrow keeps the checkmark only.
                    LayoutBuilder(
                      builder: (context, constraints) => Row(
                        children: [
                          Expanded(
                            child: Text(
                              _friendlyMediaName(job),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: CupertinoColors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          // White text and a checkmark: system blue text
                          // would disappear on the selected blue row.
                          if (selected) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              CupertinoIcons.checkmark_alt,
                              color: CupertinoColors.white,
                              size: 14,
                            ),
                            if (constraints.maxWidth >= 140) ...[
                              const SizedBox(width: 2),
                              const Text(
                                'Selected',
                                style: TextStyle(
                                  color: CupertinoColors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      details.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: CupertinoColors.white.withValues(alpha: .78),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (job.status == JobStatus.processing)
                const CupertinoActivityIndicator()
              else if (job.status == JobStatus.complete)
                const Icon(
                  CupertinoIcons.check_mark_circled_solid,
                  color: CupertinoColors.activeGreen,
                )
              else if (job.status == JobStatus.failed)
                const Icon(
                  CupertinoIcons.exclamationmark_triangle_fill,
                  color: CupertinoColors.destructiveRed,
                ),
              AppTooltip(
                message: 'Remove from queue',
                child: CupertinoButton(
                  key: Key('queue_inline_remove_${job.id}'),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(
                    kMinInteractiveDimensionCupertino,
                    kMinInteractiveDimensionCupertino,
                  ),
                  onPressed: canRemove ? () => _removeJob(job.id) : null,
                  child: Icon(
                    CupertinoIcons.trash,
                    semanticLabel:
                        'Remove ${job.displayName ?? p.basename(job.inputPath)} from queue',
                    size: 18,
                    color: canRemove
                        ? CupertinoColors.destructiveRed
                        : CupertinoColors.white.withValues(alpha: .34),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _queueInlineThumbnail(MediaJob job) {
    final placeholder = ColoredBox(
      color: CupertinoColors.white.withValues(alpha: .07),
      child: Icon(
        _iconFor(job),
        color: CupertinoColors.white.withValues(alpha: .78),
        size: 20,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 52,
        height: 52,
        child: job.kind.isImage && !job.kind.isRaw
            ? Image.file(
                File(job.inputPath),
                fit: BoxFit.cover,
                cacheWidth: 120,
                errorBuilder: (_, _, _) => placeholder,
              )
            : placeholder,
      ),
    );
  }

  /// The status card on the start screen and in the editor's iPad side pane.
  Widget _statusPanel() {
    final detailStyle = TextStyle(
      color: CupertinoColors.white.withValues(alpha: .78),
      fontSize: 13,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CupertinoColors.white.withValues(alpha: .13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Status',
            style: TextStyle(
              color: CupertinoColors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _busy ? 'Working locally' : 'Idle',
            style: TextStyle(
              color: CupertinoColors.white.withValues(alpha: .78),
              fontSize: 12,
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: CupertinoActivityIndicator(),
            ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _status!,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: detailStyle,
              ),
            ),
          if (_canShareExports)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _shareExportsButton(),
            ),
          if (_busy && _canCancelCurrentWork)
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _cancelProcessing,
              child: const Text('Cancel'),
            )
          else if (_busy)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'The export can continue if you switch apps. Return to AquaRecover to check its progress.',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: detailStyle,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickFiles() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: MediaClassifier.allExtensions,
    );
    final paths = files.map((file) => file.path).whereType<String>().toList();
    if (paths.isEmpty) {
      setState(() => _status = 'No file selected.');
      return;
    }
    await _addPaths(
      paths,
      MediaSource.files,
      destination: EditorWorkflowStep.edit,
    );
  }

  Future<void> _importFromPhotos() async {
    if (!_supportsPhotoLibrary && widget.photoMediaPicker == null) {
      await _pickFiles();
      return;
    }
    List<String>? paths;
    try {
      if (widget.photoMediaPicker != null) {
        paths = await _runPhotoPicker(widget.photoMediaPicker!);
      } else {
        final route = await _photoLibraryService.resolveImportRoute(
          fallbackShortestSide: MediaQuery.sizeOf(context).shortestSide,
        );
        if (!mounted) return;
        paths = switch (route) {
          PhotoImportRoute.systemPicker => await _runPhotoPicker(
            _pickWithSystemPicker,
          ),
          PhotoImportRoute.macSystemPicker => await _runPhotoPicker(
            _pickWithMacSystemPicker,
          ),
          PhotoImportRoute.librarySheet => await _showPhotoLibrarySheet(),
        };
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Photos import failed: ${_friendlyError(error)}';
      });
      await _showAlert('Photos import failed', _friendlyError(error));
      return;
    }
    if (paths == null || paths.isEmpty) {
      if (mounted) {
        setState(() => _status = 'No local Photos items were imported.');
      }
      return;
    }
    await _addPaths(
      paths,
      MediaSource.photos,
      destination: EditorWorkflowStep.edit,
    );
  }

  Future<List<String>> _pickWithSystemPicker() async {
    _preferAndroidPhotoPicker();
    final picked = await _imagePicker.pickMultipleMedia(
      requestFullMetadata: false,
    );
    return picked.map((file) => file.path).toList(growable: false);
  }

  Future<List<String>> _pickWithMacSystemPicker() async {
    final picked = await _photoLibraryService.pickWithMacSystemPicker();
    if (picked == null) {
      // PHPicker is unavailable (macOS 12 or older): use the in-app browser.
      return await _showPhotoLibrarySheet() ?? const [];
    }
    if (picked.failures > 0 && mounted) {
      await _showAlert(
        'Some items were skipped',
        '${picked.failures} selected item${picked.failures == 1 ? '' : 's'} could not be copied from Photos. Items stored only in iCloud must be downloaded in Photos first.',
      );
    }
    return picked.paths;
  }

  Future<List<String>?> _showPhotoLibrarySheet() {
    return showCupertinoModalPopup<List<String>>(
      context: context,
      builder: (_) => PhotoLibrarySheet(service: _photoLibraryService),
    );
  }

  /// The Android Photo Picker needs no media permission and shows only the
  /// items the user selects, unlike the legacy document picker.
  static void _preferAndroidPhotoPicker() {
    final implementation = ImagePickerPlatform.instance;
    if (implementation is ImagePickerAndroid) {
      implementation.useAndroidPhotoPicker = true;
    }
  }

  Future<List<String>> _runPhotoPicker(PhotoMediaPicker picker) async {
    setState(() {
      _busy = true;
      _status = 'Waiting for your Photos selection...';
    });
    try {
      return await picker();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _supportsPhotoLibrary =>
      Platform.isIOS || Platform.isMacOS || Platform.isAndroid;

  Future<void> _importCubeLut() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['cube'],
    );
    final path = file?.path;
    if (path == null) return;
    _setLutProfile(LutProfile.customCube(path, name: p.basename(path)));
    if (!mounted) return;
    setState(() {
      _status = 'Loaded LUT ${p.basename(path)}.';
    });
  }

  Future<void> _addPaths(
    List<String> paths,
    MediaSource source, {
    EditorWorkflowStep? destination,
  }) async {
    setState(() {
      _busy = true;
      _shareablePaths = const [];
      _status = 'Inspecting imported media...';
    });
    final now = DateTime.now().microsecondsSinceEpoch;
    Future<(int, MediaJob?)> inspectAt(int index) async {
      try {
        final metadata = await widget.inspectionService.inspect(paths[index]);
        return (
          index,
          MediaJob(
            id: '${now}_$index',
            inputPath: metadata.path,
            kind: metadata.kind,
            displayName: metadata.fileName,
            source: source,
            metadata: metadata,
          ),
        );
      } on Object {
        return (index, null);
      }
    }

    final inspected = List<MediaJob?>.filled(paths.length, null);
    const concurrentInspections = 3;
    for (var start = 0; start < paths.length; start += concurrentInspections) {
      final end = (start + concurrentInspections).clamp(0, paths.length);
      final results = await Future.wait([
        for (var index = start; index < end; index++) inspectAt(index),
      ]);
      for (final result in results) {
        inspected[result.$1] = result.$2;
      }
      if (mounted && end < paths.length) {
        setState(
          () => _status = 'Inspecting imported media... $end/${paths.length}',
        );
      }
    }
    final next = inspected.whereType<MediaJob>().toList(growable: false);
    final skipped = paths.length - next.length;
    if (!mounted) return;
    if (next.isEmpty) {
      setState(() {
        _busy = false;
        _status = 'No supported readable media files found.';
      });
      return;
    }
    setState(() {
      _storeSelectedEditState();
      final startIndex = _jobs.length;
      _jobs = [..._jobs, ...next];
      for (final job in next) {
        _editStates.putIfAbsent(job.id, () => const MediaEditState());
      }
      _selectedIndex = startIndex;
      _loadEditStateForIndex(startIndex);
      _step =
          destination ??
          (widget.libraryOnStart
              ? EditorWorkflowStep.import
              : widget.reviewExportOnStart
              ? EditorWorkflowStep.export
              : EditorWorkflowStep.edit);
      _selectedToolGroup = widget.initialToolGroup ?? EditorToolGroup.presets;
      _selectedAdjustmentId = 'recovery';
      _toolPanelOpen = true;
      _compareMode = widget.initialCompareMode ?? EditorCompareMode.edited;
      _previewFit = EditorPreviewFit.fit;
      _busy = false;
      _status = next.length > 1
          ? 'Imported ${next.length} items${skipped == 0 ? '' : ', skipped $skipped unsupported'}. Nothing is saved until you confirm export.'
          : 'Imported 1 item${skipped == 0 ? '' : ', skipped $skipped unsupported'}. Nothing is saved until you confirm export.';
    });
  }

  Future<void> _commitExport() => _startExport(selectedOnly: false);

  Future<void> _commitSelectedExport() => _startExport(selectedOnly: true);

  Future<void> _startExport({required bool selectedOnly}) async {
    if (_exportOperationActive || _jobs.isEmpty) return;
    final selectedId = _selectedJob?.id;
    if (selectedId == null) return;
    setState(() {
      _exportStartPending = true;
      _shareablePaths = const [];
      _status = 'Preparing export...';
    });
    try {
      if (!await _prepareExportDestinations() || !mounted) return;
      if (selectedOnly || _jobs.length == 1) {
        await _processSelected(selectedId);
      } else {
        await _processQueue();
      }
    } on Object catch (error) {
      if (!mounted) return;
      final message = _friendlyError(error);
      setState(() {
        _jobs = [
          for (final job in _jobs)
            if (job.status == JobStatus.processing)
              job.copyWith(
                status: JobStatus.failed,
                error: message,
                progress: 0,
              )
            else
              job,
        ];
        _status = 'Failed: $message';
      });
      await _showAlert('Export failed', message);
    } finally {
      if (mounted) {
        setState(() {
          _exportStartPending = false;
          _busy = false;
        });
      }
    }
  }

  Future<bool> _prepareExportDestinations() async {
    if (!_exportOptions.saveToFiles || _exportDirectoryPath != null) {
      return true;
    }
    return _chooseExportDirectory();
  }

  Future<void> _processSelected(String id) async {
    final selectedIndex = _jobs.indexWhere((job) => job.id == id);
    if (selectedIndex < 0) return;
    final selected = _jobs[selectedIndex];
    final exported = await _processJob(id);
    if (!exported || !mounted) return;
    setState(() {
      _removeExportedJobFromQueue(selected.id);
      _step = _jobs.isEmpty
          ? EditorWorkflowStep.import
          : EditorWorkflowStep.export;
      _status = _jobs.isEmpty
          ? 'Export complete. The queue is empty.'
          : 'Export complete. ${_jobs.length} item${_jobs.length == 1 ? '' : 's'} remaining.';
    });
  }

  Future<void> _processQueue() async {
    if (_jobs.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _cancelRequested = false;
      _status = 'Exporting all selected media...';
    });
    final batchIds = _jobs.map((job) => job.id).toList(growable: false);
    var exportedCount = 0;
    for (final id in batchIds) {
      if (!mounted || _cancelRequested) break;
      final index = _jobs.indexWhere((job) => job.id == id);
      if (index < 0) continue;
      if (_jobs[index].status == JobStatus.complete) {
        setState(() => _removeExportedJobFromQueue(id));
        continue;
      }
      final exported = await _processJob(id, partOfBatch: true);
      if (exported && mounted) {
        exportedCount++;
        setState(() => _removeExportedJobFromQueue(id));
      }
    }
    if (mounted) {
      final failed = _jobs
          .where((job) => job.status == JobStatus.failed)
          .length;
      setState(() {
        _busy = false;
        if (!_cancelRequested) {
          _step = _jobs.isEmpty
              ? EditorWorkflowStep.import
              : EditorWorkflowStep.export;
        }
        _status = _cancelRequested
            ? 'Queue cancelled.'
            : 'Batch export finished: $exportedCount exported and removed${failed == 0 ? '' : ', $failed failed'}.';
      });
    }
  }

  Future<bool> _processJob(String id, {bool partOfBatch = false}) async {
    var index = _jobs.indexWhere((job) => job.id == id);
    if (index < 0) return false;
    if (!partOfBatch && _busy) return false;
    var job = _jobs[index];
    if (job.kind.isVideo &&
        !VideoRestorationService.isBackendAvailableOnCurrentPlatform) {
      final message = _videoUnavailableMessage;
      setState(() {
        _storeSelectedEditState();
        _selectedIndex = index;
        _loadEditStateForIndex(index);
        _updateJob(
          index,
          (old) => old.copyWith(
            status: JobStatus.failed,
            error: message,
            progress: 0,
          ),
        );
        _status = message;
      });
      if (!partOfBatch) await _showAlert('Video export unavailable', message);
      return false;
    }
    RawVideoDescriptor? rawDescriptor;
    if (job.kind == MediaKind.rawVideo) {
      if (partOfBatch) {
        rawDescriptor = _rawDescriptor;
      } else {
        final descriptor = await RawVideoDialog.show(
          context,
          initial: _rawDescriptor,
        );
        if (descriptor == null || !mounted) return false;
        _rawDescriptor = descriptor;
        rawDescriptor = descriptor;
      }
    }
    index = _jobs.indexWhere((item) => item.id == id);
    if (index < 0 || !mounted) return false;
    setState(() {
      _storeSelectedEditState();
      if (!partOfBatch) {
        _busy = true;
        _cancelRequested = false;
      }
      _selectedIndex = index;
      _loadEditStateForIndex(index);
      _status =
          'Exporting ${job.displayName ?? p.basename(job.inputPath)} on this device...';
      _updateJob(
        index,
        (old) => old.copyWith(
          status: JobStatus.processing,
          progress: .1,
          clearError: true,
        ),
      );
    });
    String? generatedOutput;
    try {
      final trim = _currentTrimSettings();
      index = _jobs.indexWhere((item) => item.id == id);
      if (index < 0) return false;
      job = _jobs[index];
      final output = switch (job.kind) {
        MediaKind.photo => await _restorePhoto(job.inputPath),
        MediaKind.rawPhoto => await _rawService.restoreRawImage(
          job.inputPath,
          _settings,
          exportOptions: _exportOptions,
          lutProfile: _lutProfile,
          transform: _transformSettings,
        ),
        MediaKind.video => await _videoService.restoreVideo(
          job.inputPath,
          _settings,
          trim: trim,
          exportOptions: _exportOptions,
          lutProfile: _lutProfile,
        ),
        MediaKind.rawVideo => await _videoService.restoreVideo(
          job.inputPath,
          _settings,
          rawDescriptor: rawDescriptor,
          trim: trim,
          exportOptions: _exportOptions,
          lutProfile: _lutProfile,
        ),
      };
      generatedOutput = output;
      if (_exportOptions.keepLocalCopy) {
        await _sidecarService.write(
          inputPath: job.inputPath,
          outputPath: output,
          settings: _settings,
          exportOptions: _exportOptions,
          lutProfile: _lutProfile,
          trim: trim,
          transform: _transformSettings,
          rawVideoDescriptor: rawDescriptor,
        );
      }
      if (_exportOptions.saveToPhotoLibrary) {
        await _photoLibraryService.saveExport(
          output,
          job.kind,
          creationDate: await CaptureMetadata.captureDateForFile(job.inputPath),
        );
      }
      if (_exportOptions.saveToFiles) {
        final directoryPath = _exportDirectoryPath;
        if (directoryPath == null) {
          throw StateError('Choose a Files export folder before exporting.');
        }
        await _folderExportService.copyToDirectory(
          sourcePath: output,
          directoryPath: directoryPath,
        );
      }
      if (!_exportOptions.keepLocalCopy) {
        await _deleteGeneratedOutput(output);
      }
      if (!mounted) return false;
      setState(() {
        _updateJobById(
          id,
          (old) => old.copyWith(
            status: JobStatus.complete,
            outputPath: _exportOptions.keepLocalCopy ? output : null,
            progress: 1,
            clearError: true,
            clearOutput: !_exportOptions.keepLocalCopy,
          ),
        );
        if (!partOfBatch) _step = EditorWorkflowStep.export;
        if (_exportOptions.keepLocalCopy) {
          _shareablePaths = [..._shareablePaths, output];
        }
        _status =
            'Exported ${p.basename(output)} to ${_exportDestinationNames().join(', ')}.';
      });
      return true;
    } on Object catch (error) {
      if (!_exportOptions.keepLocalCopy && generatedOutput != null) {
        await _deleteGeneratedOutput(generatedOutput);
      }
      if (!mounted) return false;
      final message = _friendlyError(error);
      setState(() {
        _updateJobById(
          id,
          (old) => old.copyWith(
            status: JobStatus.failed,
            error: message,
            progress: 0,
          ),
        );
        _status = 'Failed: $message';
      });
      if (!partOfBatch) await _showAlert('Export failed', message);
      return false;
    } finally {
      if (mounted && !partOfBatch) setState(() => _busy = false);
    }
  }

  Future<String> _restorePhoto(String inputPath) {
    if (MediaClassifier.requiresPlatformImageDecode(inputPath)) {
      return _rawService.restorePlatformDecodedImage(
        inputPath,
        _settings,
        exportOptions: _exportOptions,
        lutProfile: _lutProfile,
        transform: _transformSettings,
      );
    }
    return _imageService.restoreFile(
      inputPath,
      _settings,
      exportOptions: _exportOptions,
      lutProfile: _lutProfile,
      transform: _transformSettings,
    );
  }

  Future<void> _deleteGeneratedOutput(String outputPath) async {
    for (final path in [outputPath, '$outputPath.aquarecover.json']) {
      final file = File(path);
      if (await file.exists()) {
        try {
          await file.delete();
        } on FileSystemException {
          // Best effort: failed Photos-only exports must not be listed locally.
        }
      }
    }
  }

  VideoEditSettings _currentTrimSettings() {
    final startText = _trimStartController.text.trim();
    final endText = _trimEndController.text.trim();
    final start = startText.isEmpty ? 0.0 : double.tryParse(startText);
    final end = endText.isEmpty ? null : double.tryParse(endText);
    if (start == null) {
      throw const FormatException('Trim start must be a number of seconds.');
    }
    if (endText.isNotEmpty && end == null) {
      throw const FormatException('Trim end must be a number of seconds.');
    }
    final settings = VideoEditSettings(
      enabled: _trimEnabled,
      startSeconds: start,
      endSeconds: end,
    );
    settings.validate();
    return settings;
  }

  void _updateJob(int index, MediaJob Function(MediaJob old) update) {
    final copy = [..._jobs];
    copy[index] = update(copy[index]);
    _jobs = copy;
  }

  void _updateJobById(String id, MediaJob Function(MediaJob old) update) {
    final index = _jobs.indexWhere((job) => job.id == id);
    if (index >= 0) _updateJob(index, update);
  }

  void _removeExportedJobFromQueue(String id) {
    _storeSelectedEditState();
    final result = removeMediaJobFromQueue(
      jobs: _jobs,
      selectedIndex: _selectedIndex,
      id: id,
    );
    _editStates.remove(id);
    _histories.remove(id);
    _videoPreviewPositions.remove(id);
    _videoDurations.remove(id);
    _videoPreviewUnavailable.remove(id);
    _jobs = result.jobs;
    _selectedIndex = result.selectedIndex;
    if (_jobs.isNotEmpty) _loadEditStateForIndex(_selectedIndex);
  }

  Future<void> _showQueueOverview() {
    if (_jobs.isEmpty) return Future.value();
    final openEditorOnSelect = _step == EditorWorkflowStep.import;
    return showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => QueueOverviewSheet(
        jobs: _jobs,
        selectedJobId: _selectedJob?.id,
        busy: _exportOperationActive,
        onSelected: (id) => _selectJob(id, openEditor: openEditorOnSelect),
        onRemove: _removeJob,
      ),
    );
  }

  Future<void> _pickNeutralPoint() async {
    final job = _selectedJob;
    if (job == null) return;
    final picked = await NeutralPointPicker.show(
      context,
      path: job.inputPath,
      settings: _settings,
      lutProfile: _lutProfile,
    );
    if (picked == null || !mounted || _selectedJob?.id != job.id) return;
    _setRestorationSettings(picked);
    setState(() => _selectedAdjustmentId = 'temperature');
  }

  /// Returns the cached suggestion for [job] and starts analysing it when the
  /// selection changed. The panel rebuilds once the analysis arrives.
  SceneAnalysis? _suggestionFor(MediaJob? job) {
    if (job == null || !SceneSuggestionService.supports(job.kind)) return null;
    final path = job.inputPath;
    if (_suggestionPath != path) {
      _suggestionPath = path;
      _suggestion = null;
      unawaited(
        _sceneSuggestions.suggest(path, job.kind).then((analysis) {
          if (!mounted || _suggestionPath != path) return;
          setState(() => _suggestion = analysis);
        }),
      );
    }
    return _suggestion;
  }

  void _selectJob(String id, {bool openEditor = false}) {
    final index = _jobs.indexWhere((job) => job.id == id);
    if (index < 0 || _exportOperationActive) return;
    _selectJobIndex(index, openEditor: openEditor);
  }

  void _selectJobIndex(int index, {bool openEditor = false}) {
    if (index < 0 || index >= _jobs.length || _exportOperationActive) {
      return;
    }
    setState(() {
      _storeSelectedEditState();
      _selectedIndex = index;
      _loadEditStateForIndex(index);
      if (openEditor) _step = EditorWorkflowStep.edit;
    });
  }

  bool _removeJob(String id) {
    final index = _jobs.indexWhere((job) => job.id == id);
    if (index < 0) return false;
    final removed = _jobs[index];
    if (removed.status == JobStatus.processing || _exportOperationActive) {
      return false;
    }
    final result = removeMediaJobFromQueue(
      jobs: _jobs,
      selectedIndex: _selectedIndex,
      id: id,
    );
    final remaining = result.jobs;
    setState(() {
      _storeSelectedEditState();
      _editStates.remove(id);
      _histories.remove(id);
      _videoPreviewPositions.remove(id);
      _videoDurations.remove(id);
      _jobs = remaining;
      _selectedIndex = result.selectedIndex;
      if (remaining.isNotEmpty) _loadEditStateForIndex(_selectedIndex);
      if (remaining.isEmpty) {
        _step = EditorWorkflowStep.import;
      }
      _status = 'Removed ${_friendlyMediaName(removed)} from the queue.';
    });
    return true;
  }

  void _cancelProcessing() {
    if (!_canCancelCurrentWork) {
      setState(
        () => _status =
            'This export cannot be cancelled safely. It will finish shortly.',
      );
      return;
    }
    _cancelRequested = true;
    _videoService.cancelAll();
    setState(() => _status = 'Cancel requested.');
  }

  void _applyExportPreset(ExportPreset preset) {
    setState(() {
      _exportPreset = preset;
      _exportOptions = preset.options.copyWith(
        keepLocalCopy: _exportOptions.keepLocalCopy,
        saveToPhotoLibrary: _exportOptions.saveToPhotoLibrary,
        saveToFiles: _exportOptions.saveToFiles,
        beforeAfter: _exportOptions.beforeAfter,
        beforeAfterLayout: _exportOptions.beforeAfterLayout,
        beforeAfterLabels: _exportOptions.beforeAfterLabels,
      );
      _applyJpegQuality(preset.jpegQuality);
    });
  }

  void _setJpegQuality(int quality) {
    setState(() => _applyJpegQuality(quality));
  }

  void _applyJpegQuality(int quality) {
    _storeSelectedEditState();
    _settings = _settings.copyWith(jpegQuality: quality);
    _editStates = {
      for (final entry in _editStates.entries)
        entry.key: entry.value.copyWith(
          settings: entry.value.settings.copyWith(jpegQuality: quality),
        ),
    };
    _storeSelectedEditState();
  }

  void _setKeepLocalCopy(bool value) {
    setState(() {
      _exportOptions = _exportOptions.withKeepLocalCopy(value);
    });
  }

  void _setSaveToPhotoLibrary(bool value) {
    setState(() {
      _exportOptions = _exportOptions.withPhotoLibrary(value);
    });
  }

  Future<void> _setSaveToFiles(bool value) async {
    if (!value) {
      setState(() {
        _exportOptions = _exportOptions.withFiles(false);
        _exportDirectoryPath = null;
      });
      return;
    }
    await _chooseExportDirectory();
  }

  Future<bool> _chooseExportDirectory() async {
    try {
      final path = await FilePicker.getDirectoryPath(
        dialogTitle: 'Choose export folder',
      );
      if (path == null || !mounted) return false;
      final directory = Directory(path);
      if (!await directory.exists()) {
        throw FileSystemException(
          'The selected export folder is unavailable.',
          path,
        );
      }
      if (!mounted) return false;
      setState(() {
        _exportDirectoryPath = path;
        _exportOptions = _exportOptions.withFiles(true);
      });
      return true;
    } on Object catch (error) {
      if (mounted) {
        await _showAlert(
          'Folder unavailable',
          'AquaRecover could not use the selected folder. ${_friendlyError(error)}',
        );
      }
      return false;
    }
  }

  String get _videoUnavailableMessage =>
      VideoRestorationService.backendUnavailableReason;

  Future<void> _showAlert(String title, String message) {
    return showAppDialog<void>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(message),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _openMovies() {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(builder: (_) => const TimelineProjectsPage()),
    );
  }

  /// Starts a movie from the queue, keeping each item's grade and look.
  Future<void> _makeMovieFromQueue() async {
    final selected = _selectedJob;
    if (selected != null) _editStates[selected.id] = _currentEditState;
    final project = movieFromQueue(
      _jobs,
      editStates: _editStates,
      videoDurations: _videoDurations,
      id: TimelineProjectsPage.newProjectId(),
      name: TimelineProjectsPage.defaultName(DateTime.now()),
    );
    await TimelineProjectsPage.open(context, project);
  }

  void _openLogbook() {
    Navigator.of(
      context,
    ).push(CupertinoPageRoute<void>(builder: (_) => const LogbookPage()));
  }

  void _openLocalExports() {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => ExportLibraryPage(shareService: widget.shareService),
      ),
    );
  }

  bool get _canShareExports =>
      _shareablePaths.isNotEmpty &&
      !_exportOperationActive &&
      widget.shareService.isAvailable;

  /// Share next to the finished export: one file, or every file a batch
  /// kept, in a single share sheet.
  Widget _shareExportsButton() {
    final count = _shareablePaths.length;
    return AppTooltip(
      message: count == 1
          ? 'Share the exported file'
          : 'Share all $count exported files',
      child: Builder(
        builder: (buttonContext) => CupertinoButton(
          key: const Key('share_exports'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          minimumSize: const Size(
            kMinInteractiveDimensionCupertino,
            kMinInteractiveDimensionCupertino,
          ),
          borderRadius: BorderRadius.circular(12),
          color: CupertinoColors.activeBlue,
          disabledColor: CupertinoColors.activeBlue.withValues(alpha: .38),
          foregroundColor: CupertinoColors.white,
          onPressed: _sharing
              ? null
              : () => _shareExports(shareOriginOf(buttonContext)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(CupertinoIcons.share, size: 20),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  count == 1 ? 'Share' : 'Share all $count',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareExports(Rect? origin) async {
    if (_sharing || _shareablePaths.isEmpty) return;
    setState(() => _sharing = true);
    try {
      await widget.shareService.shareFiles(_shareablePaths, origin: origin);
    } on Object catch (error) {
      if (mounted) await showShareFailedDialog(context, error);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _showAbout() {
    showAppDialog<void>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('AquaRecover'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Version $aquaRecoverVersion\n\nOn-device underwater color recovery for photos, RAW stills, videos, LUTs, and local exports.',
          ),
        ),
        actions: [
          if (widget.onShowTutorial != null)
            CupertinoDialogAction(
              onPressed: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) widget.onShowTutorial?.call();
                });
              },
              child: const Text('Quick Tour'),
            ),
          CupertinoDialogAction(
            onPressed: () {
              final navigator = Navigator.of(context);
              navigator.pop();
              navigator.push(
                CupertinoPageRoute<void>(
                  builder: (_) => const AppLicensePage(),
                ),
              );
            },
            child: const Text('Licenses'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  String _friendlyError(Object error) {
    final message = error.toString().replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return message.length <= 260 ? message : '${message.substring(0, 260)}...';
  }

  Widget _floatingGlass({
    required Widget child,
    required EdgeInsetsGeometry padding,
    double borderRadius = 20,
  }) {
    return EditorGlassSurface(
      style: EditorGlassStyle.clear,
      borderRadius: borderRadius,
      padding: padding,
      child: child,
    );
  }

  Widget _choicePill({
    required String label,
    required bool selected,
    required VoidCallback? onPressed,
    BuildContext? styleContext,
  }) {
    final resolvedContext = styleContext ?? context;
    final primary = CupertinoTheme.of(resolvedContext).primaryColor;
    // A compact capsule inside the 44 pt hit region, like the preset chips.
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(
        kMinInteractiveDimensionCupertino,
        kMinInteractiveDimensionCupertino,
      ),
      onPressed: onPressed,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: const StadiumBorder(),
          color: onPressed == null
              ? CupertinoDynamicColor.resolve(
                  CupertinoColors.quaternarySystemFill,
                  resolvedContext,
                )
              : selected
              ? primary.withValues(alpha: .16)
              : CupertinoDynamicColor.resolve(
                  CupertinoColors.systemBackground,
                  resolvedContext,
                ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? primary
                  : CupertinoDynamicColor.resolve(
                      CupertinoColors.label,
                      resolvedContext,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _darkPill(String label) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.black.withValues(alpha: .50),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: CupertinoColors.white.withValues(alpha: .16)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
            color: CupertinoColors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  double _previewAspectRatio(MediaJob job) {
    final width = job.metadata?.width;
    final height = job.metadata?.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return 4 / 3;
    }
    // Crop geometry must use the real source ratio. Clamping it makes the
    // overlay disagree with portrait and panoramic media and can place the
    // requested crop outside the actual image.
    return width / height;
  }

  Widget _switchRow({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    Key? controlKey,
    BuildContext? styleContext,
    String? tooltip,
  }) {
    final resolvedContext = styleContext ?? context;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: CupertinoTheme.of(
                resolvedContext,
              ).textTheme.textStyle.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          CupertinoSwitch(
            key: controlKey,
            value: value,
            onChanged: _exportOperationActive ? null : onChanged,
          ),
        ],
      ),
    );
    if (tooltip == null) return row;
    return AppTooltip(message: tooltip, child: row);
  }

  Widget _numberField({
    required String label,
    required TextEditingController controller,
    required bool enabled,
    String? placeholder,
    BuildContext? styleContext,
  }) {
    final resolvedContext = styleContext ?? context;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _secondaryText(resolvedContext)),
        const SizedBox(height: 4),
        CupertinoTextField(
          enabled: enabled && !_busy,
          controller: controller,
          placeholder: placeholder,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
      ],
    );
  }

  TextStyle _secondaryText(BuildContext context) {
    return CupertinoTheme.of(context).textTheme.textStyle.copyWith(
      fontSize: 13,
      color: CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel,
        context,
      ),
    );
  }

  TextStyle _panelTitle([BuildContext? styleContext]) {
    final resolvedContext = styleContext ?? context;
    return CupertinoTheme.of(
      resolvedContext,
    ).textTheme.textStyle.copyWith(fontWeight: FontWeight.w700);
  }

  IconData _iconFor(MediaJob job) {
    return job.kind.isVideo
        ? CupertinoIcons.film
        : job.kind.isRaw
        ? CupertinoIcons.doc_richtext
        : CupertinoIcons.photo;
  }
}

/// Keeps the floating title and controls legible over bright photos
/// without text shadows: a solid band behind the top bar that fades out
/// below it, and a lighter fade behind the bottom tools.
class _PhotoScrim extends StatelessWidget {
  const _PhotoScrim({required this.topInset, required this.bottom});

  final double topInset;

  /// Opacity of the fade at the bottom edge.
  final double bottom;

  static const _band = .58;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          if (!height.isFinite || height <= 0) return const SizedBox.shrink();
          final bandEnd = ((topInset + 64) / height).clamp(0.0, .4);
          final fadeEnd = ((topInset + 112) / height).clamp(bandEnd, .5);
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  CupertinoColors.black.withValues(alpha: _band),
                  CupertinoColors.black.withValues(alpha: _band),
                  CupertinoColors.black.withValues(alpha: 0),
                  CupertinoColors.black.withValues(alpha: 0),
                  CupertinoColors.black.withValues(alpha: bottom),
                ],
                stops: [0, bandEnd, fadeEnd, .55, 1],
              ),
            ),
          );
        },
      ),
    );
  }
}
