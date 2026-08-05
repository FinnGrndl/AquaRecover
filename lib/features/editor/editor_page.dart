import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../../core/media/media_classifier.dart';
import '../../core/media/media_inspection_service.dart';
import '../../core/models/export_options.dart';
import '../../core/models/image_transform_settings.dart';
import '../../core/models/lut_profile.dart';
import '../../core/models/media_job.dart';
import '../../core/models/media_kind.dart';
import '../../core/models/raw_video_descriptor.dart';
import '../../core/models/restoration_settings.dart';
import '../../core/models/video_edit_settings.dart';
import '../../core/photo/photo_library_service.dart';
import '../../core/persistence/folder_export_service.dart';
import '../../core/persistence/sidecar_service.dart';
import '../../core/platform/raw_processing_service.dart';
import '../../core/processing/image_restoration_service.dart';
import '../../core/processing/video_restoration_service.dart';
import '../../core/utils/output_paths.dart';
import '../../core/workflow/editor_workflow.dart';
import '../../shared/widgets/glass_panel.dart';
import '../library/export_library_page.dart';
import 'editor_tools.dart';
import 'widgets/adjustment_browser.dart';
import 'widgets/app_license_page.dart';
import 'widgets/crop_browser.dart';
import 'widgets/editor_bottom_panel.dart';
import 'widgets/editor_preview_stage.dart';
import 'widgets/editor_tool_rail.dart';
import 'widgets/exported_photo_preview.dart';
import 'widgets/preset_browser.dart';
import 'widgets/photo_library_sheet.dart';
import 'widgets/queue_overview_sheet.dart';
import 'widgets/raw_video_dialog.dart';
import 'widgets/setting_slider.dart';
import 'widgets/video_frame_preview_tile.dart';
import 'widgets/video_preview_tile.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    this.initialPaths = const [],
    this.openPhotosOnStart = false,
    this.initialToolGroup,
    this.initialCompareMode,
    this.reviewExportOnStart = false,
  });

  final List<String> initialPaths;
  final bool openPhotosOnStart;
  final EditorToolGroup? initialToolGroup;
  final EditorCompareMode? initialCompareMode;
  final bool reviewExportOnStart;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final _imageService = const ImageRestorationService();
  final _videoService = const VideoRestorationService();
  final _rawService = RawProcessingService();
  final _photoLibraryService = const PhotoLibraryService();
  final _folderExportService = const FolderExportService();
  final _sidecarService = const SidecarService();
  final _inspectionService = const MediaInspectionService();
  final _imagePicker = ImagePicker();
  final _trimStartController = TextEditingController(text: '0');
  final _trimEndController = TextEditingController();

  List<MediaJob> _jobs = const [];
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
  bool _busy = false;
  bool _cancelRequested = false;
  double _cropGestureStartZoom = 1;
  String? _status = 'Ready.';

  MediaJob? get _selectedJob {
    if (_jobs.isEmpty) return null;
    return _jobs[_selectedIndex.clamp(0, _jobs.length - 1).toInt()];
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final safeInsets = MediaQuery.paddingOf(context);
              final wide = constraints.maxWidth >= 1040;
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _editStep(
                        wide: true,
                        topInset: safeInsets.top,
                        bottomInset: safeInsets.bottom,
                      ),
                    ),
                    SizedBox(
                      width: 390,
                      child: SafeArea(
                        left: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 20, 20, 20),
                          child: _sidePane(),
                        ),
                      ),
                    ),
                  ],
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
      );
    }
    return _importScaffold();
  }

  Widget _importScaffold() {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xff041923),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xff07384b), Color(0xff07596b), Color(0xff03151e)],
              stops: [0, .50, 1],
            ),
          ),
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
                  return CupertinoScrollbar(
                    child: ListView(
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
                                _importStep(showQueue: true),
                                if (_shouldShowStartStatus) ...[
                                  const SizedBox(height: 16),
                                  _statusPanel(),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
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
    return Row(
      children: [
        Container(
          width: 54,
          height: 54,
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            color: CupertinoColors.white.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: CupertinoColors.white.withValues(alpha: .28),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13.5),
            child: Image.asset(
              'assets/branding/aquarecover_app_icon.png',
              key: const Key('start_brand_icon'),
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AquaRecover',
                style: TextStyle(
                  color: CupertinoColors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.3,
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
        ),
        CupertinoButton(
          key: const Key('start_about'),
          padding: EdgeInsets.zero,
          minimumSize: const Size(42, 42),
          borderRadius: BorderRadius.circular(99),
          color: CupertinoColors.white.withValues(alpha: .11),
          onPressed: _showAbout,
          child: const Icon(
            CupertinoIcons.info,
            color: CupertinoColors.white,
            size: 20,
          ),
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
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          CupertinoColors.black.withValues(alpha: .50),
                          CupertinoColors.black.withValues(alpha: .06),
                          CupertinoColors.black.withValues(alpha: .54),
                        ],
                        stops: const [0, .42, 1],
                      ),
                    ),
                  ),
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
            boxShadow: wide
                ? [
                    BoxShadow(
                      color: CupertinoColors.black.withValues(alpha: .24),
                      blurRadius: 28,
                      offset: const Offset(0, 16),
                    ),
                  ]
                : null,
          ),
          child: CupertinoTheme(
            data: CupertinoTheme.of(context).copyWith(
              brightness: Brightness.dark,
              primaryColor: CupertinoColors.activeBlue,
            ),
            child: Builder(
              builder: (panelContext) => CupertinoScrollbar(
                child: ListView(
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

  Widget _sidePane() {
    return CupertinoScrollbar(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 20, 20, 24),
        children: [_statusPanel(), const SizedBox(height: 12), _queueSection()],
      ),
    );
  }

  Widget _importStep({required bool showQueue}) {
    final job = _selectedJob;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _importHero(job),
        if (job != null) ...[const SizedBox(height: 14), _importSummary(job)],
        if (showQueue && _jobs.isNotEmpty) ...[
          const SizedBox(height: 16),
          _queueSection(compact: true),
        ],
      ],
    );
  }

  Widget _importHero(MediaJob? job) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Restore underwater color',
          style: CupertinoTheme.of(context).textTheme.navLargeTitleTextStyle
              .copyWith(
                color: CupertinoColors.white,
                fontWeight: FontWeight.w700,
                fontSize: 38,
                letterSpacing: -1,
                height: 1.05,
              ),
        ),
        const SizedBox(height: 13),
        Text(
          'Choose one photo or video to edit. Select several to prepare one batch, then export everything with one confirmation.',
          style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
            color: CupertinoColors.white.withValues(alpha: .72),
            fontSize: 17,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 28),
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
              Text('Choose from Photos'),
            ],
          ),
        ),
        const SizedBox(height: 10),
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
              Text(
                'Import Files',
                style: TextStyle(color: CupertinoColors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        CupertinoButton(
          key: const Key('start_local_exports'),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          borderRadius: BorderRadius.circular(16),
          onPressed: _openLocalExports,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                CupertinoIcons.tray_full,
                size: 19,
                color: CupertinoColors.white,
              ),
              SizedBox(width: 8),
              Text(
                'Local Exports',
                style: TextStyle(color: CupertinoColors.white),
              ),
            ],
          ),
        ),
        if (job != null) ...[
          const SizedBox(height: 10),
          CupertinoButton(
            color: CupertinoColors.white.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(16),
            onPressed: _busy
                ? null
                : () => setState(() => _step = EditorWorkflowStep.edit),
            child: const Text(
              'Edit selected',
              style: TextStyle(color: CupertinoColors.white),
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
        final reservedPreview = compact ? 250.0 : 320.0;
        final reservedChrome = compact ? 174.0 : 182.0;
        final availablePanelHeight =
            constraints.maxHeight -
            reservedPreview -
            reservedChrome -
            topInset -
            bottomInset;
        final preferredPanelHeight = compact
            ? switch (activeGroup) {
                EditorToolGroup.light => 260.0,
                EditorToolGroup.presets => 255.0,
                EditorToolGroup.crop => 250.0,
                EditorToolGroup.effects => 240.0,
                EditorToolGroup.video => 275.0,
                _ => 255.0,
              }
            : switch (activeGroup) {
                EditorToolGroup.light => 280.0,
                EditorToolGroup.presets => 275.0,
                EditorToolGroup.crop => 270.0,
                EditorToolGroup.effects => 260.0,
                EditorToolGroup.video => 300.0,
                _ => 275.0,
              };
        final panelHeight = availablePanelHeight <= 120
            ? 0.0
            : availablePanelHeight.clamp(0.0, preferredPanelHeight).toDouble();
        final panelOpen = _toolPanelOpen && panelHeight > 0;
        return Stack(
          fit: StackFit.expand,
          children: [
            EditorHoldPreview(
              compareMode: _compareMode,
              previewBuilder: (mode) => EditorPreviewStage(
                job: job,
                settings: _settings,
                compareMode: mode,
                lutProfile: _lutProfile,
                immersive: true,
                showHeader: false,
                borderRadius: 0,
                immersiveBottomInset:
                    (panelOpen ? panelHeight + 102 : 112) + bottomInset,
                transform: _transformSettings,
                showCropGrid: activeGroup == EditorToolGroup.crop,
              ),
              onScaleStart: activeGroup == EditorToolGroup.crop
                  ? _startCropGesture
                  : null,
              onScaleUpdate: activeGroup == EditorToolGroup.crop
                  ? _updateCropGesture
                  : null,
              heldIndicator: Positioned(
                top:
                    topInset +
                    (_jobs.length > 1
                        ? (compact ? 128 : 132)
                        : (compact ? 76 : 80)),
                left: horizontalPadding,
                child: _darkPill('Original'),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        CupertinoColors.black.withValues(alpha: .46),
                        CupertinoColors.black.withValues(alpha: .05),
                        CupertinoColors.black.withValues(alpha: .42),
                      ],
                      stops: const [0, .45, 1],
                    ),
                  ),
                ),
              ),
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
              top:
                  topInset +
                  (_jobs.length > 1
                      ? (compact ? 122 : 126)
                      : (compact ? 70 : 74)),
              right: horizontalPadding,
              child: _previewCompareButton(
                mode: _compareMode,
                onPressed: _toggleComparePreview,
              ),
            ),
            Positioned(
              left: horizontalPadding,
              right: horizontalPadding,
              bottom: bottomPadding,
              child: CupertinoTheme(
                data: CupertinoTheme.of(context).copyWith(
                  brightness: Brightness.dark,
                  primaryColor: CupertinoColors.activeBlue,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EditorBottomPanel(
                      group: activeGroup,
                      open: panelOpen,
                      height: panelHeight,
                      onClose: () => setState(() => _toolPanelOpen = false),
                      child: _toolPanelContent(activeGroup),
                    ),
                    if (panelOpen) const SizedBox(height: 2),
                    if (!panelOpen)
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
                      panelOpen: panelOpen,
                      onSelected: _selectToolGroup,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _previewCompareButton({
    required EditorCompareMode mode,
    required VoidCallback onPressed,
  }) {
    final showingSplit = mode.isSplit;
    final actionLabel = showingSplit
        ? 'Show edited preview'
        : 'Show split preview';
    final background = showingSplit
        ? CupertinoColors.activeBlue.withValues(alpha: .94)
        : CupertinoColors.black.withValues(alpha: .56);
    return Tooltip(
      message: actionLabel,
      child: Semantics(
        button: true,
        selected: showingSplit,
        label: actionLabel,
        child: CupertinoButton(
          key: const Key('editor_preview_compare'),
          padding: EdgeInsets.zero,
          minimumSize: const Size(42, 42),
          borderRadius: BorderRadius.circular(99),
          color: background,
          onPressed: onPressed,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
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
    );
  }

  void _toggleComparePreview() {
    setState(() => _compareMode = _compareMode.toggled);
  }

  void _startCropGesture(ScaleStartDetails details) {
    _cropGestureStartZoom = _transformSettings.zoom;
  }

  void _updateCropGesture(ScaleUpdateDetails details) {
    if (_busy) return;
    final zoom = (_cropGestureStartZoom * details.scale)
        .clamp(1.0, 4.0)
        .toDouble();
    final movementScale = 150 * zoom;
    final offsetX =
        (_transformSettings.offsetX -
                details.focalPointDelta.dx / movementScale)
            .clamp(-1.0, 1.0)
            .toDouble();
    final offsetY =
        (_transformSettings.offsetY -
                details.focalPointDelta.dy / movementScale)
            .clamp(-1.0, 1.0)
            .toDouble();
    setState(() {
      _transformSettings = _transformSettings.copyWith(
        zoom: zoom,
        offsetX: offsetX,
        offsetY: offsetY,
      );
    });
  }

  Widget _editorTopBar(MediaJob job) {
    final title = job.displayName ?? p.basename(job.inputPath);
    return _floatingGlass(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      borderRadius: 22,
      child: Row(
        children: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            minimumSize: Size.zero,
            onPressed: _busy
                ? null
                : () => setState(() => _step = EditorWorkflowStep.import),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.chevron_left,
                  size: 18,
                  color: CupertinoColors.white,
                ),
                SizedBox(width: 4),
                Text('Library', style: TextStyle(color: CupertinoColors.white)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: CupertinoTheme.of(context).textTheme.textStyle
                      .copyWith(
                        color: CupertinoColors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  '${_settings.preset.label} - ${job.kind.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: CupertinoTheme.of(context).textTheme.textStyle
                      .copyWith(
                        color: CupertinoColors.white.withValues(alpha: .72),
                        fontSize: 12,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Review export',
            child: Semantics(
              button: true,
              label: 'Review export',
              child: CupertinoButton(
                key: const Key('editor_review_export'),
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 38),
                borderRadius: BorderRadius.circular(16),
                color: CupertinoColors.systemGrey.withValues(alpha: .72),
                onPressed: _busy
                    ? null
                    : () => setState(() => _step = EditorWorkflowStep.export),
                child: const Icon(
                  CupertinoIcons.check_mark,
                  color: CupertinoColors.white,
                  size: 21,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _exportTopBar(MediaJob job) {
    final videoUnavailable =
        job.kind.isVideo &&
        !VideoRestorationService.isBackendAvailableOnCurrentPlatform;
    final complete = _jobs.every((item) => item.status == JobStatus.complete);
    return _floatingGlass(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      borderRadius: 22,
      child: Row(
        children: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            minimumSize: Size.zero,
            onPressed: _busy
                ? null
                : () => setState(() => _step = EditorWorkflowStep.edit),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.chevron_left,
                  size: 18,
                  color: CupertinoColors.white,
                ),
                SizedBox(width: 4),
                Text('Edit', style: TextStyle(color: CupertinoColors.white)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  complete ? 'Complete' : 'Export',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: CupertinoTheme.of(context).textTheme.textStyle
                      .copyWith(
                        color: CupertinoColors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  _friendlyMediaName(job),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: CupertinoTheme.of(context).textTheme.textStyle
                      .copyWith(
                        color: CupertinoColors.white.withValues(alpha: .72),
                        fontSize: 12,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          CupertinoButton.filled(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: Size.zero,
            onPressed: (_busy || videoUnavailable)
                ? null
                : complete
                ? () => setState(() => _step = EditorWorkflowStep.import)
                : _commitExport,
            child: Text(
              _busy
                  ? 'Exporting...'
                  : complete
                  ? 'Done'
                  : _jobs.length > 1
                  ? 'Export all'
                  : 'Export',
            ),
          ),
        ],
      ),
    );
  }

  Widget _editorBatchStrip(MediaJob job, {required bool compact}) {
    final total = _jobs.length;
    final current = _selectedIndex.clamp(0, total - 1).toInt() + 1;
    final complete = _jobs
        .where((item) => item.status == JobStatus.complete)
        .length;
    final failed = _jobs
        .where((item) => item.status == JobStatus.failed)
        .length;
    final pending = total - complete - failed;
    return _floatingGlass(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      borderRadius: 20,
      child: Row(
        children: [
          _editorIconButton(
            icon: CupertinoIcons.chevron_left,
            onPressed: _busy || _selectedIndex <= 0
                ? null
                : () => setState(() => _selectedIndex--),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: CupertinoButton(
              key: const Key('editor_open_queue'),
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
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
                          '$pending ready - $complete complete${failed == 0 ? '' : ' - $failed failed'}',
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
            icon: CupertinoIcons.chevron_right,
            onPressed: _busy || _selectedIndex >= total - 1
                ? null
                : () => setState(() => _selectedIndex++),
          ),
        ],
      ),
    );
  }

  Widget _editorIconButton({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return CupertinoButton(
      padding: const EdgeInsets.all(7),
      minimumSize: Size.zero,
      borderRadius: BorderRadius.circular(99),
      color: CupertinoColors.white.withValues(
        alpha: onPressed == null ? .08 : .16,
      ),
      onPressed: onPressed,
      child: Icon(
        icon,
        color: CupertinoColors.white.withValues(
          alpha: onPressed == null ? .34 : 1,
        ),
        size: 17,
      ),
    );
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
          onChanged: (settings) => setState(() => _settings = settings),
        ),
        EditorToolGroup.light => AdjustmentBrowser(
          controls: allImageAdjustmentControls,
          settings: _settings,
          presetSettings: _settings.presetBaseline,
          selectedId: _selectedAdjustmentId,
          enabled: !_busy,
          onSelected: (id) => setState(() => _selectedAdjustmentId = id),
          onChanged: (settings) => setState(() => _settings = settings),
        ),
        EditorToolGroup.crop => CropBrowser(
          settings: _transformSettings,
          enabled: !_busy,
          onChanged: (settings) =>
              setState(() => _transformSettings = settings),
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
                : (value) => setState(
                    () => _settings = control.apply(_settings, value),
                  ),
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
        if (job.status == JobStatus.complete && job.outputPath != null) ...[
          const SizedBox(height: 12),
          _resultPanel(job),
        ],
        const SizedBox(height: 14),
        if (_jobs.length > 1) ...[
          _batchExportReviewPanel(),
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
                  onPressed: _busy
                      ? null
                      : () => setState(() => _step = EditorWorkflowStep.edit),
                  child: const Text('Back to edit'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CupertinoButton.filled(
                  onPressed: (_busy || videoUnavailable) ? null : _commitExport,
                  child: Text(
                    _busy
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
            color: CupertinoColors.activeBlue,
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

  Widget _importSummary(MediaJob job) {
    return _splitCards(
      left: _mediaCard(
        title: 'Selected media',
        path: job.inputPath,
        kind: job.kind,
        previewMode: _PreviewMode.frame,
      ),
      right: _metadataCard(job),
    );
  }

  Widget _metadataCard(MediaJob job) {
    final metadata = job.metadata;
    final rows = <(String, String)>[
      (
        'File',
        metadata?.fileName ?? job.displayName ?? p.basename(job.inputPath),
      ),
      ('Type', metadata?.kind.label ?? job.kind.label),
      ('Source', job.source.label),
      ('Status', job.status.label),
      if (metadata?.sizeLabel != null) ('Size', metadata!.sizeLabel),
      if (metadata?.dimensionsLabel != null)
        ('Resolution', metadata!.dimensionsLabel!),
      if (metadata?.durationLabel != null)
        ('Duration', metadata!.durationLabel!),
    ];
    return _previewCard(
      title: 'Details',
      trailing: job.kind.label,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final row in rows) _metadataRow(row.$1, row.$2)],
        ),
      ),
      footer: job.inputPath,
      minHeight: 280,
    );
  }

  Widget _metadataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(label, style: _secondaryText(context)),
          ),
          Expanded(
            child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
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
              color: CupertinoColors.activeBlue,
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
    if (job.status == JobStatus.complete &&
        job.outputPath != null &&
        job.kind.isImage) {
      return ExportedPhotoPreview(
        path: job.outputPath!,
        aspectRatio: _transformSettings.outputAspectRatio(sourceAspectRatio),
      );
    }
    return AspectRatio(
      aspectRatio: _transformSettings.outputAspectRatio(sourceAspectRatio),
      child: EditorPreviewStage(
        job: job,
        settings: _settings,
        compareMode: EditorCompareMode.split,
        lutProfile: _lutProfile,
        showHeader: false,
        borderRadius: 16,
        transform: _transformSettings,
      ),
    );
  }

  Widget _mediaCard({
    required String title,
    required String path,
    required MediaKind kind,
    _PreviewMode previewMode = _PreviewMode.live,
  }) {
    final ext = p.extension(path).replaceFirst('.', '').toUpperCase();
    final canShowImage = kind.isImage && !kind.isRaw;
    final canShowVideo = kind == MediaKind.video && File(path).existsSync();
    final child = SizedBox(
      height: 236,
      width: double.infinity,
      child: canShowImage
          ? Image.file(
              File(path),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => _placeholder(kind),
            )
          : canShowVideo
          ? previewMode == _PreviewMode.frame
                ? VideoFramePreviewTile(path: path)
                : VideoPreviewTile(path: path)
          : _placeholder(kind),
    );
    return _previewCard(
      title: title,
      trailing: ext.isEmpty ? kind.label : ext,
      child: child,
      footer: path,
    );
  }

  Widget _previewCard({
    required String title,
    required String trailing,
    required Widget child,
    String? footer,
    double minHeight = 280,
  }) {
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: _tileDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tileHeader(title, trailing),
          child,
          if (footer != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                footer,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _secondaryText(context),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder(MediaKind kind) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            kind.isVideo ? CupertinoIcons.film : CupertinoIcons.doc_richtext,
            size: 48,
            color: CupertinoDynamicColor.resolve(
              CupertinoColors.secondaryLabel,
              context,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            kind.isVideo
                ? 'Frame preview unavailable for this format'
                : 'Preview generated during export',
            style: _secondaryText(context),
          ),
        ],
      ),
    );
  }

  Widget _resultPanel(MediaJob job) {
    final output = job.outputPath!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CupertinoColors.white.withValues(alpha: .13)),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.check_mark_circled_solid,
            color: CupertinoColors.activeGreen,
            size: 25,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Export saved',
                  style: TextStyle(
                    color: CupertinoColors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _exportResultMessage(output),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CupertinoColors.systemGrey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (_exportOptions.keepLocalCopy)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              minimumSize: Size.zero,
              onPressed: _openLocalExports,
              child: const Text('View'),
            ),
        ],
      ),
    );
  }

  String _exportResultMessage(String outputPath) {
    final destinations = _exportDestinationNames();
    if (destinations.length == 1 && _exportOptions.keepLocalCopy) {
      return 'Saved locally as ${p.basename(outputPath)}.';
    }
    final joined = switch (destinations.length) {
      0 => 'the selected destination',
      1 => destinations.single,
      2 => '${destinations.first} and ${destinations.last}',
      _ =>
        '${destinations.sublist(0, destinations.length - 1).join(', ')}, and ${destinations.last}',
    };
    final localNote = _exportOptions.keepLocalCopy
        ? ''
        : ' No local copy was kept.';
    return 'Saved to $joined.$localNote';
  }

  List<String> _exportDestinationNames() => [
    if (_exportOptions.keepLocalCopy) 'AquaRecover',
    if (_exportOptions.saveToPhotoLibrary) 'Photos',
    if (_exportOptions.saveToFiles) 'Files',
  ];

  Widget _batchExportReviewPanel() {
    final complete = _jobs
        .where((job) => job.status == JobStatus.complete)
        .length;
    final failed = _jobs.where((job) => job.status == JobStatus.failed).length;
    final pending = _jobs.length - complete - failed;
    final selected = _selectedJob;
    final videoUnavailable =
        selected != null &&
        selected.kind.isVideo &&
        !VideoRestorationService.isBackendAvailableOnCurrentPlatform;
    final canExportSelected =
        selected != null &&
        !_busy &&
        !videoUnavailable &&
        selected.status.canStartIndividualExport;
    final actionLabel = switch (selected?.status) {
      JobStatus.failed => 'Retry selected',
      JobStatus.complete => 'Export selected again',
      JobStatus.processing => 'Exporting selected...',
      _ => 'Export selected',
    };
    return _sectionBox(
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
                    Text('Batch export', style: _panelTitle()),
                    const SizedBox(height: 3),
                    Text(
                      '$pending ready - $complete complete${failed == 0 ? '' : ' - $failed failed'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _secondaryText(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CupertinoButton(
                key: const Key('export_open_queue'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                minimumSize: Size.zero,
                onPressed: _busy ? null : _showQueueOverview,
                child: const Text('Manage'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: BoxDecoration(
              color: CupertinoColors.systemGrey5.resolveFrom(context),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Selected item',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        selected == null
                            ? 'No item selected'
                            : _friendlyMediaName(selected),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _secondaryText(context).copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                CupertinoButton(
                  key: const Key('export_selected_batch'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  minimumSize: Size.zero,
                  borderRadius: BorderRadius.circular(11),
                  color: CupertinoColors.systemGrey4.resolveFrom(context),
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

  Widget _splitCards({required Widget left, required Widget right}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(children: [left, const SizedBox(height: 12), right]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        );
      },
    );
  }

  Widget _videoSection(BuildContext panelContext) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Frame preview updates with the same color settings; full video export depends on the backend.',
          style: _secondaryText(panelContext),
        ),
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
    );
  }

  Widget _lutSection(BuildContext panelContext) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final profile in LutProfile.builtIns)
              _choicePill(
                label: profile.name,
                selected: _lutProfile.kind == profile.kind,
                styleContext: panelContext,
                onPressed: _busy
                    ? null
                    : () => setState(
                        () => _lutProfile = profile.copyWith(
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
              : (v) => setState(
                  () => _lutProfile = _lutProfile.copyWith(intensity: v),
                ),
        ),
      ],
    );
  }

  Widget _exportOptionsSection(BuildContext panelContext) {
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
            thumbColor: CupertinoColors.activeBlue,
            children: {
              for (final preset in ExportPreset.values)
                preset: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    preset.label,
                    style: const TextStyle(color: CupertinoColors.white),
                  ),
                ),
            },
            onValueChanged: (value) {
              if (value != null) _applyExportPreset(value);
            },
          ),
          const SizedBox(height: 8),
          CupertinoSlidingSegmentedControl<ImageOutputFormat>(
            groupValue: _exportOptions.imageFormat,
            backgroundColor: CupertinoColors.white.withValues(alpha: .10),
            thumbColor: CupertinoColors.activeBlue,
            children: const {
              ImageOutputFormat.jpeg: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'JPEG',
                  style: TextStyle(color: CupertinoColors.white),
                ),
              ),
              ImageOutputFormat.png: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'PNG',
                  style: TextStyle(color: CupertinoColors.white),
                ),
              ),
            },
            onValueChanged: (value) {
              if (value != null) {
                setState(() {
                  _exportPreset = ExportPreset.proEdit;
                  _exportOptions = _exportOptions.copyWith(imageFormat: value);
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
                    color: CupertinoColors.activeBlue,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    minimumSize: Size.zero,
                    onPressed: _busy
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
            'Choose one or more destinations. Photos and Files exports do not appear under Local Exports unless a local copy is enabled.',
            style: CupertinoTheme.of(panelContext).textTheme.textStyle.copyWith(
              color: CupertinoColors.systemGrey,
              fontSize: 12,
            ),
          ),
          SettingSlider(
            label: 'JPEG quality',
            value: _settings.jpegQuality.toDouble(),
            min: 70,
            max: 100,
            divisions: 30,
            format: (v) => v.round().toString(),
            onChanged: (v) => setState(
              () => _settings = _settings.copyWith(jpegQuality: v.round()),
            ),
          ),
          _switchRow(
            title: 'Strip metadata',
            value: _exportOptions.stripMetadata,
            styleContext: panelContext,
            onChanged: (v) => setState(
              () => _exportOptions = _exportOptions.copyWith(stripMetadata: v),
            ),
          ),
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

  Widget _queueSection({bool compact = false}) {
    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Queue',
          '${_jobs.length} item${_jobs.length == 1 ? '' : 's'}',
        ),
        const SizedBox(height: 8),
        if (_jobs.isEmpty)
          Text('No media imported.', style: _secondaryText(context))
        else
          Column(
            children: [
              for (var i = 0; i < _jobs.length; i++) _queueRow(i, _jobs[i]),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: CupertinoButton(
                  onPressed: _busy ? null : _clearCompleted,
                  child: const Text('Clear completed'),
                ),
              ),
            ],
          ),
      ],
    );
    return compact ? _sectionBox(child: child) : GlassPanel(child: child);
  }

  Widget _queueRow(int index, MediaJob job) {
    final selected = index == _selectedIndex;
    return GestureDetector(
      onTap: _busy
          ? null
          : () => setState(() {
              _selectedIndex = index;
            }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected
              ? CupertinoTheme.of(context).primaryColor.withValues(alpha: 0.12)
              : CupertinoDynamicColor.resolve(
                  CupertinoColors.secondarySystemGroupedBackground,
                  context,
                ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? CupertinoTheme.of(
                    context,
                  ).primaryColor.withValues(alpha: 0.42)
                : CupertinoDynamicColor.resolve(
                    CupertinoColors.separator,
                    context,
                  ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              _iconFor(job),
              color: CupertinoDynamicColor.resolve(
                CupertinoColors.secondaryLabel,
                context,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.displayName ?? p.basename(job.inputPath),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${job.kind.label} - ${job.status.label}',
                    style: _secondaryText(context),
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
            const SizedBox(width: 4),
            CupertinoButton(
              key: Key('queue_inline_remove_${job.id}'),
              padding: const EdgeInsets.all(7),
              minimumSize: Size.zero,
              onPressed:
                  (!_busy || job.status == JobStatus.pending) &&
                      job.status != JobStatus.processing
                  ? () => _removeJob(job.id)
                  : null,
              child: Icon(
                CupertinoIcons.trash,
                semanticLabel:
                    'Remove ${job.displayName ?? p.basename(job.inputPath)} from queue',
                size: 18,
                color:
                    (!_busy || job.status == JobStatus.pending) &&
                        job.status != JobStatus.processing
                    ? CupertinoColors.destructiveRed
                    : CupertinoColors.systemGrey3.resolveFrom(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPanel() {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Status', _busy ? 'Working locally' : 'Idle'),
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
                style: _secondaryText(context),
              ),
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
                'Export cannot be cancelled safely. Keep the app open until this item finishes.',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: _secondaryText(context),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: MediaClassifier.allExtensions,
      allowMultiple: true,
      withData: false,
    );
    final paths =
        result?.files.map((file) => file.path).whereType<String>().toList() ??
        const <String>[];
    if (paths.isEmpty) {
      setState(() => _status = 'No file selected.');
      return;
    }
    await _addPaths(paths, MediaSource.files);
  }

  Future<void> _importFromPhotos() async {
    List<String>? paths;
    if (Platform.isIOS) {
      setState(() {
        _busy = true;
        _status = 'Waiting for your Photos selection...';
      });
      try {
        final picked = await _imagePicker.pickMultipleMedia(
          requestFullMetadata: false,
        );
        paths = picked.map((file) => file.path).toList(growable: false);
      } on Object catch (error) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _status = 'Photos import failed: ${_friendlyError(error)}';
        });
        await _showAlert('Photos import failed', _friendlyError(error));
        return;
      }
      if (mounted) setState(() => _busy = false);
    } else {
      paths = await showCupertinoModalPopup<List<String>>(
        context: context,
        builder: (_) => PhotoLibrarySheet(service: _photoLibraryService),
      );
    }
    if (paths == null || paths.isEmpty) {
      if (mounted) {
        setState(() => _status = 'No local Photos items were imported.');
      }
      return;
    }
    await _addPaths(paths, MediaSource.photos);
  }

  Future<void> _importCubeLut() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['cube'],
      allowMultiple: false,
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() {
      _lutProfile = LutProfile.customCube(path, name: p.basename(path));
      _status = 'Loaded LUT ${p.basename(path)}.';
    });
  }

  Future<void> _addPaths(List<String> paths, MediaSource source) async {
    setState(() {
      _busy = true;
      _status = 'Inspecting imported media...';
    });
    final now = DateTime.now().microsecondsSinceEpoch;
    Future<(int, MediaJob?)> inspectAt(int index) async {
      try {
        final metadata = await _inspectionService.inspect(paths[index]);
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
      final startIndex = _jobs.length;
      _jobs = [..._jobs, ...next];
      _selectedIndex = startIndex;
      _step = widget.reviewExportOnStart
          ? EditorWorkflowStep.export
          : EditorWorkflowStep.edit;
      _settings = RestorationPreset.auto.settings;
      _transformSettings = const ImageTransformSettings();
      _selectedToolGroup = widget.initialToolGroup ?? EditorToolGroup.presets;
      _selectedAdjustmentId = 'recovery';
      _toolPanelOpen = true;
      _compareMode = widget.initialCompareMode ?? EditorCompareMode.edited;
      _busy = false;
      _status = next.length > 1
          ? 'Imported ${next.length} items${skipped == 0 ? '' : ', skipped $skipped unsupported'}. Nothing is saved until you confirm export.'
          : 'Imported 1 item${skipped == 0 ? '' : ', skipped $skipped unsupported'}. Nothing is saved until you confirm export.';
    });
  }

  Future<void> _commitExport() async {
    if (!await _prepareExportDestinations()) return;
    await (_jobs.length > 1 ? _processQueue() : _processSelected());
  }

  Future<void> _commitSelectedExport() async {
    if (!await _prepareExportDestinations()) return;
    await _processSelected();
  }

  Future<bool> _prepareExportDestinations() async {
    if (!_exportOptions.saveToFiles || _exportDirectoryPath != null) {
      return true;
    }
    return _chooseExportDirectory();
  }

  Future<void> _processSelected() async {
    if (_selectedJob == null) return;
    await _processJob(_selectedIndex);
  }

  Future<void> _processQueue() async {
    if (_jobs.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _cancelRequested = false;
      _status = 'Exporting all selected media...';
    });
    for (var i = 0; i < _jobs.length; i++) {
      if (!mounted || _cancelRequested) break;
      if (_jobs[i].status == JobStatus.complete) continue;
      await _processJob(i, partOfBatch: true);
    }
    if (mounted) {
      final complete = _jobs
          .where((job) => job.status == JobStatus.complete)
          .length;
      final failed = _jobs
          .where((job) => job.status == JobStatus.failed)
          .length;
      setState(() {
        _busy = false;
        if (!_cancelRequested) _step = EditorWorkflowStep.export;
        _status = _cancelRequested
            ? 'Queue cancelled.'
            : 'Batch export finished: $complete complete${failed == 0 ? '' : ', $failed failed'}.';
      });
    }
  }

  Future<void> _processJob(int index, {bool partOfBatch = false}) async {
    if (index < 0 || index >= _jobs.length) return;
    if (!partOfBatch && _busy) return;
    var job = _jobs[index];
    if (job.kind.isVideo &&
        !VideoRestorationService.isBackendAvailableOnCurrentPlatform) {
      final message = _videoUnavailableMessage;
      setState(() {
        _selectedIndex = index;
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
      return;
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
        if (descriptor == null || !mounted) return;
        _rawDescriptor = descriptor;
        rawDescriptor = descriptor;
      }
    }
    setState(() {
      if (!partOfBatch) {
        _busy = true;
        _cancelRequested = false;
      }
      _selectedIndex = index;
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
        await _photoLibraryService.saveExport(output, job.kind);
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
      final previewOutput = _exportOptions.keepLocalCopy
          ? output
          : await _moveToTemporaryPreview(output);
      if (!mounted) return;
      setState(() {
        _updateJob(
          index,
          (old) => old.copyWith(
            status: JobStatus.complete,
            outputPath: previewOutput,
            progress: 1,
            clearError: true,
          ),
        );
        if (!partOfBatch) _step = EditorWorkflowStep.export;
        _status =
            'Exported ${p.basename(output)} to ${_exportDestinationNames().join(', ')}.';
      });
    } on Object catch (error) {
      if (!_exportOptions.keepLocalCopy && generatedOutput != null) {
        await _deleteGeneratedOutput(generatedOutput);
      }
      if (!mounted) return;
      final message = _friendlyError(error);
      setState(() {
        _updateJob(
          index,
          (old) => old.copyWith(
            status: JobStatus.failed,
            error: message,
            progress: 0,
          ),
        );
        _status = 'Failed: $message';
      });
      if (!partOfBatch) await _showAlert('Export failed', message);
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

  Future<String> _moveToTemporaryPreview(String outputPath) async {
    final directory = await OutputPaths.intermediateDirectory();
    final previewPath = p.join(
      directory.path,
      'export_preview_${p.basename(outputPath)}',
    );
    final source = File(outputPath);
    final preview = File(previewPath);
    if (await preview.exists()) await preview.delete();
    try {
      await source.rename(previewPath);
    } on FileSystemException {
      await source.copy(previewPath);
      await source.delete();
    }
    final sidecar = File('$outputPath.aquarecover.json');
    if (await sidecar.exists()) await sidecar.delete();
    return previewPath;
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

  void _clearCompleted() {
    final remaining = _jobs
        .where((job) => job.status != JobStatus.complete)
        .toList();
    setState(() {
      _jobs = remaining;
      _selectedIndex = remaining.isEmpty
          ? 0
          : _selectedIndex.clamp(0, remaining.length - 1).toInt();
      if (remaining.isEmpty) _step = EditorWorkflowStep.import;
      _status = 'Cleared completed items.';
    });
  }

  Future<void> _showQueueOverview() {
    if (_jobs.isEmpty) return Future.value();
    return showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => QueueOverviewSheet(
        jobs: _jobs,
        selectedJobId: _selectedJob?.id,
        busy: _busy,
        onSelected: _selectJob,
        onRemove: _removeJob,
      ),
    );
  }

  void _selectJob(String id) {
    final index = _jobs.indexWhere((job) => job.id == id);
    if (index < 0 || _busy) return;
    setState(() => _selectedIndex = index);
  }

  bool _removeJob(String id) {
    final index = _jobs.indexWhere((job) => job.id == id);
    if (index < 0) return false;
    final removed = _jobs[index];
    if (removed.status == JobStatus.processing ||
        (_busy && removed.status != JobStatus.pending)) {
      return false;
    }
    final remaining = [..._jobs]..removeAt(index);
    setState(() {
      _jobs = remaining;
      if (remaining.isEmpty) {
        _selectedIndex = 0;
        _step = EditorWorkflowStep.import;
      } else if (index < _selectedIndex) {
        _selectedIndex--;
      } else if (_selectedIndex >= remaining.length) {
        _selectedIndex = remaining.length - 1;
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
      );
      _settings = _settings.copyWith(jpegQuality: preset.jpegQuality);
    });
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
    return showCupertinoDialog<void>(
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

  void _openLocalExports() {
    Navigator.of(
      context,
    ).push(CupertinoPageRoute<void>(builder: (_) => const ExportLibraryPage()));
  }

  void _showAbout() {
    showCupertinoDialog<void>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('AquaRecover'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Version 0.4.0\n\nOn-device underwater color recovery for photos, RAW stills, videos, LUTs, and local exports.',
          ),
        ),
        actions: [
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: CupertinoColors.black.withValues(alpha: .34),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: CupertinoColors.white.withValues(alpha: .18),
            ),
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.black.withValues(alpha: .20),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }

  Widget _sectionBox({
    required Widget child,
    EdgeInsetsGeometry margin = EdgeInsets.zero,
  }) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
          CupertinoColors.secondarySystemGroupedBackground,
          context,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: CupertinoDynamicColor.resolve(
            CupertinoColors.separator,
            context,
          ),
        ),
      ),
      child: child,
    );
  }

  Widget _sectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
        ),
        const SizedBox(height: 3),
        Text(subtitle, style: _secondaryText(context)),
      ],
    );
  }

  Widget _choicePill({
    required String label,
    required bool selected,
    required VoidCallback? onPressed,
    BuildContext? styleContext,
  }) {
    final resolvedContext = styleContext ?? context;
    return CupertinoButton(
      minimumSize: Size.zero,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: selected
          ? CupertinoTheme.of(
              resolvedContext,
            ).primaryColor.withValues(alpha: .16)
          : CupertinoDynamicColor.resolve(
              CupertinoColors.systemBackground,
              resolvedContext,
            ),
      borderRadius: BorderRadius.circular(99),
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          color: selected
              ? CupertinoTheme.of(resolvedContext).primaryColor
              : CupertinoDynamicColor.resolve(
                  CupertinoColors.label,
                  resolvedContext,
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
    return (width / height).clamp(.68, 1.65).toDouble();
  }

  Widget _switchRow({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    Key? controlKey,
    BuildContext? styleContext,
  }) {
    final resolvedContext = styleContext ?? context;
    return Padding(
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
            onChanged: _busy ? null : onChanged,
          ),
        ],
      ),
    );
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

  Widget _tileHeader(String title, String trailing) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: CupertinoTheme.of(
                context,
              ).textTheme.textStyle.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Text(trailing, style: _secondaryText(context)),
        ],
      ),
    );
  }

  BoxDecoration _tileDecoration(BuildContext context) {
    return BoxDecoration(
      color: CupertinoDynamicColor.resolve(
        CupertinoColors.secondarySystemGroupedBackground,
        context,
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: CupertinoDynamicColor.resolve(
          CupertinoColors.separator,
          context,
        ),
      ),
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

enum _PreviewMode { live, frame }
