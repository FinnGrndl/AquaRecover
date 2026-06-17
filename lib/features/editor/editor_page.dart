import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:path/path.dart' as p;

import '../../core/media/media_classifier.dart';
import '../../core/media/media_inspection_service.dart';
import '../../core/models/export_options.dart';
import '../../core/models/lut_profile.dart';
import '../../core/models/media_job.dart';
import '../../core/models/media_kind.dart';
import '../../core/models/raw_video_descriptor.dart';
import '../../core/models/restoration_settings.dart';
import '../../core/models/video_edit_settings.dart';
import '../../core/photo/photo_library_service.dart';
import '../../core/persistence/sidecar_service.dart';
import '../../core/platform/raw_processing_service.dart';
import '../../core/processing/image_restoration_service.dart';
import '../../core/processing/video_restoration_service.dart';
import '../../core/workflow/editor_workflow.dart';
import '../../shared/widgets/glass_panel.dart';
import 'editor_tools.dart';
import 'widgets/before_after_scrubber.dart';
import 'widgets/editor_bottom_panel.dart';
import 'widgets/editor_preview_stage.dart';
import 'widgets/editor_tool_rail.dart';
import 'widgets/photo_library_sheet.dart';
import 'widgets/raw_video_dialog.dart';
import 'widgets/restored_image_preview.dart';
import 'widgets/setting_slider.dart';
import 'widgets/video_frame_preview_tile.dart';
import 'widgets/video_preview_tile.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final _imageService = const ImageRestorationService();
  final _videoService = const VideoRestorationService();
  final _rawService = RawProcessingService();
  final _photoLibraryService = const PhotoLibraryService();
  final _sidecarService = const SidecarService();
  final _inspectionService = const MediaInspectionService();
  final _trimStartController = TextEditingController(text: '0');
  final _trimEndController = TextEditingController();

  List<MediaJob> _jobs = const [];
  int _selectedIndex = 0;
  EditorWorkflowStep _step = EditorWorkflowStep.import;
  RawVideoDescriptor _rawDescriptor = RawVideoDescriptor.default4k;
  RestorationSettings _settings = RestorationPreset.auto.settings;
  ExportPreset _exportPreset = ExportPreset.archive;
  ExportOptions _exportOptions = ExportPreset.archive.options;
  LutProfile _lutProfile = LutProfile.none;
  bool _trimEnabled = false;
  EditorToolGroup _selectedToolGroup = EditorToolGroup.presets;
  bool _toolPanelOpen = true;
  EditorCompareMode _compareMode = EditorCompareMode.edited;
  double _previewSplit = .5;
  bool _busy = false;
  bool _cancelRequested = false;
  String? _status = 'Ready.';

  MediaJob? get _selectedJob {
    if (_jobs.isEmpty) return null;
    return _jobs[_selectedIndex.clamp(0, _jobs.length - 1).toInt()];
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
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1040;
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _editStep(wide: true)),
                    SizedBox(
                      width: 390,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 20, 20, 20),
                        child: _sidePane(),
                      ),
                    ),
                  ],
                );
              }
              return _editStep(wide: false);
            },
          ),
        ),
      );
    }
    return CupertinoPageScaffold(
      backgroundColor: CupertinoDynamicColor.resolve(
        CupertinoColors.systemGroupedBackground,
        context,
      ),
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('AquaRecover'),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _showAbout,
              child: const Icon(CupertinoIcons.info_circle),
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: _step != EditorWorkflowStep.edit,
            child: SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 1040;
                  if (_step == EditorWorkflowStep.edit) {
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _editStep(wide: true)),
                          SizedBox(width: 390, child: _sidePane()),
                        ],
                      );
                    }
                    return _editStep(wide: false);
                  }
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _workflowPane(wide: true)),
                        SizedBox(width: 390, child: _sidePane()),
                      ],
                    );
                  }
                  return CupertinoScrollbar(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        _workflowPane(wide: false),
                        if (_shouldShowInlineStatus) ...[
                          const SizedBox(height: 12),
                          _statusPanel(),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _exportOverlayScaffold(MediaJob job) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 820;
            final horizontalPadding = wide ? 24.0 : 12.0;
            final panel = _exportFloatingPanel(wide: wide);
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
                  top: 8,
                  left: horizontalPadding,
                  right: horizontalPadding,
                  child: _exportTopBar(job),
                ),
                if (wide)
                  Positioned(
                    top: 72,
                    right: 24,
                    bottom: 24,
                    width: 460,
                    child: panel,
                  )
                else
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    height: constraints.maxHeight * .70,
                    child: panel,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _exportFloatingPanel({required bool wide}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: CupertinoDynamicColor.resolve(
              CupertinoColors.systemBackground,
              context,
            ).withValues(alpha: .91),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: CupertinoColors.white.withValues(alpha: .18),
            ),
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.black.withValues(alpha: .24),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: CupertinoScrollbar(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, wide ? 18 : 24),
              children: [_exportStep(showActions: false)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _workflowPane({required bool wide}) {
    final content = GlassPanel(child: _stepBody(wide: wide));
    if (!wide) return content;
    return CupertinoScrollbar(
      child: ListView(padding: const EdgeInsets.all(20), children: [content]),
    );
  }

  bool get _shouldShowInlineStatus {
    if (_step != EditorWorkflowStep.import) return true;
    if (_busy || _jobs.isNotEmpty) return true;
    final status = _status?.trim();
    return status != null && status.isNotEmpty && status != 'Ready.';
  }

  Widget _sidePane() {
    return CupertinoScrollbar(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 20, 20, 24),
        children: [_statusPanel(), const SizedBox(height: 12), _queueSection()],
      ),
    );
  }

  Widget _stepBody({required bool wide}) {
    return switch (_step) {
      EditorWorkflowStep.import => _importStep(showQueue: !wide),
      EditorWorkflowStep.edit => _editStep(wide: wide),
      EditorWorkflowStep.export => _exportStep(),
    };
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
    final hasBatch = _jobs.length > 1;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CupertinoTheme.of(context).primaryColor.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: CupertinoTheme.of(context).primaryColor.withValues(alpha: .22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            CupertinoIcons.photo_on_rectangle,
            color: CupertinoColors.activeBlue,
            size: 30,
          ),
          const SizedBox(height: 10),
          Text(
            'Import media',
            style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
          ),
          const SizedBox(height: 4),
          Text(
            'Choose photos or videos first. AquaRecover opens the editor as soon as readable media is imported.',
            style: _secondaryText(context),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              CupertinoButton.filled(
                onPressed: _busy ? null : _pickFiles,
                child: const Text('Import Files'),
              ),
              CupertinoButton(
                onPressed: _busy ? null : _importFromPhotos,
                child: const Text('Import from Photos'),
              ),
              if (job != null)
                CupertinoButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _step = EditorWorkflowStep.edit),
                  child: const Text('Edit selected'),
                ),
              if (hasBatch)
                CupertinoButton(
                  onPressed: _busy ? null : _processQueue,
                  child: const Text('Export batch'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _editStep({required bool wide}) {
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
        final bottomPadding = compact ? 10.0 : 18.0;
        final reservedPreview = compact ? 250.0 : 320.0;
        final reservedChrome = compact ? 174.0 : 182.0;
        final availablePanelHeight =
            constraints.maxHeight - reservedPreview - reservedChrome;
        final panelHeight = availablePanelHeight <= 96
            ? 0.0
            : availablePanelHeight.clamp(
                compact ? 176.0 : 210.0,
                compact ? 270.0 : 340.0,
              );
        final panelOpen = _toolPanelOpen && panelHeight > 0;
        return Stack(
          fit: StackFit.expand,
          children: [
            EditorPreviewStage(
              job: job,
              settings: _settings,
              compareMode: _compareMode,
              lutProfile: _lutProfile,
              immersive: true,
              showHeader: false,
              borderRadius: 0,
            ),
            Positioned.fill(
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
            Positioned(
              top: 8,
              left: horizontalPadding,
              right: horizontalPadding,
              child: _editorTopBar(job),
            ),
            if (_jobs.length > 1)
              Positioned(
                top: compact ? 66 : 70,
                left: horizontalPadding,
                right: horizontalPadding,
                child: _editorBatchStrip(job, compact: compact),
              ),
            Positioned(
              left: horizontalPadding,
              right: horizontalPadding,
              bottom: bottomPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_jobs.length <= 1) _editorSingleStatusStrip(job),
                  if (_jobs.length <= 1) const SizedBox(height: 8),
                  EditorBottomPanel(
                    group: activeGroup,
                    open: panelOpen,
                    height: panelHeight,
                    onClose: () => setState(() => _toolPanelOpen = false),
                    child: _toolPanelContent(job, activeGroup),
                  ),
                  if (panelOpen) const SizedBox(height: 2),
                  if (!panelOpen)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _collapsedPanelHint(activeGroup),
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
          ],
        );
      },
    );
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
                Text('Import', style: TextStyle(color: CupertinoColors.white)),
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
                  '${job.kind.label} - ${job.status.label}',
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
            onPressed: _busy
                ? null
                : () => setState(() => _step = EditorWorkflowStep.export),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Export'),
                SizedBox(width: 4),
                Icon(CupertinoIcons.chevron_right, size: 18),
              ],
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
                  'Export',
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
            onPressed: (_busy || videoUnavailable) ? null : _processSelected,
            child: Text(_busy ? 'Exporting...' : 'Export'),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  compact
                      ? 'Batch $current/$total'
                      : 'Batch $current of $total - ${job.displayName ?? p.basename(job.inputPath)}',
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
                  '$pending pending - $complete complete${failed == 0 ? '' : ' - $failed failed'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
          _editorIconButton(
            icon: CupertinoIcons.chevron_right,
            onPressed: _busy || _selectedIndex >= total - 1
                ? null
                : () => setState(() => _selectedIndex++),
          ),
          const SizedBox(width: 8),
          CupertinoButton.filled(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            minimumSize: Size.zero,
            onPressed: _busy ? null : _processQueue,
            child: Text(compact ? 'All' : 'Export all'),
          ),
        ],
      ),
    );
  }

  Widget _editorSingleStatusStrip(MediaJob job) {
    return Align(
      alignment: Alignment.centerLeft,
      child: _floatingGlass(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        borderRadius: 99,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.wand_stars,
              color: CupertinoColors.white,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              _settings.preset.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                color: CupertinoColors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              job.kind == MediaKind.video
                  ? '${_compareMode.label} frame'
                  : _compareMode.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                color: CupertinoColors.white.withValues(alpha: .74),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _collapsedPanelHint(EditorToolGroup group) {
    return _floatingGlass(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      borderRadius: 99,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            group.label,
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
              color: CupertinoColors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 6),
          const Icon(
            CupertinoIcons.chevron_up,
            color: CupertinoColors.white,
            size: 14,
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

  Widget _toolPanelContent(MediaJob job, EditorToolGroup group) {
    return switch (group) {
      EditorToolGroup.presets => _presetSection(),
      EditorToolGroup.light ||
      EditorToolGroup.color ||
      EditorToolGroup.details => _adjustmentSliders(group.adjustments),
      EditorToolGroup.effects => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _adjustmentSliders(group.adjustments),
          _panelDivider(),
          _lutSection(),
        ],
      ),
      EditorToolGroup.compare => _compareSection(job),
      EditorToolGroup.video => _videoSection(),
    };
  }

  Widget _adjustmentSliders(List<AdjustmentControl> controls) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Manual adjustments', style: _panelTitle())),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: _busy ? null : _resetSettings,
              child: const Text('Reset'),
            ),
          ],
        ),
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

  Widget _compareSection(MediaJob job) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Preview mode', style: _panelTitle()),
        const SizedBox(height: 10),
        CupertinoSlidingSegmentedControl<EditorCompareMode>(
          groupValue: _compareMode,
          children: {
            for (final mode in EditorCompareMode.values)
              mode: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(mode.label),
              ),
          },
          onValueChanged: (value) {
            if (value != null) setState(() => _compareMode = value);
          },
        ),
        const SizedBox(height: 12),
        Text(
          job.kind == MediaKind.video
              ? 'Video uses a representative frame while you tune settings.'
              : 'Split shows original and adjusted previews side by side.',
          style: _secondaryText(context),
        ),
      ],
    );
  }

  Widget _panelDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        height: 1,
        color: CupertinoDynamicColor.resolve(
          CupertinoColors.separator,
          context,
        ),
      ),
    );
  }

  Widget _exportStep({bool showActions = true}) {
    final job = _selectedJob;
    if (job == null) return _noSelectionState();
    final videoUnavailable =
        job.kind.isVideo &&
        !VideoRestorationService.isBackendAvailableOnCurrentPlatform;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _selectedMediaHeader(job),
        const SizedBox(height: 14),
        _sectionHeader(
          'Export review',
          job.kind.isVideo ? 'Frame preview before export' : 'Before and after',
        ),
        const SizedBox(height: 12),
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
        _exportOptionsSection(),
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
                  onPressed: (_busy || videoUnavailable)
                      ? null
                      : _processSelected,
                  child: Text(_busy ? 'Exporting...' : 'Export selected'),
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

  Widget _selectedMediaHeader(MediaJob job) {
    final title = _friendlyMediaName(job);
    final subtitle = _mediaSummary(job);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _pill(job.kind.label),
            _pill(job.source.label),
            _pill(job.status.label),
            if (job.metadata?.sizeLabel != null) _pill(job.metadata!.sizeLabel),
            if (_lutProfile.isEnabled) _pill('LUT: ${_lutProfile.name}'),
            if (_trimEnabled && job.kind.isVideo) _pill('Trim enabled'),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          title,
          style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _secondaryText(context),
        ),
        if (job.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              job.error!,
              style: _secondaryText(
                context,
              ).copyWith(color: CupertinoColors.destructiveRed),
            ),
          ),
      ],
    );
  }

  Widget _exportPreview(MediaJob job) {
    if (job.status == JobStatus.complete &&
        job.outputPath != null &&
        job.kind.isImage) {
      return BeforeAfterScrubber(
        originalPath: job.inputPath,
        restoredPath: job.outputPath!,
        kind: job.kind,
        aspectRatio: _previewAspectRatio(job),
      );
    }
    if (job.kind == MediaKind.photo) {
      return _liveBeforeAfterPreview(job);
    }
    if (job.kind == MediaKind.video) {
      return _videoFrameComparison(job, exportReview: true);
    }
    if (job.status == JobStatus.complete && job.outputPath != null) {
      return _mediaCard(
        title: 'Exported file',
        path: job.outputPath!,
        kind: job.kind,
      );
    }
    return _mediaCard(title: 'Preview', path: job.inputPath, kind: job.kind);
  }

  Widget _videoFrameComparison(MediaJob job, {bool exportReview = false}) {
    final caption = exportReview ? 'Export frame' : 'Preview frame';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _splitCards(
          left: _videoFrameCard(
            title: 'Before frame',
            path: job.inputPath,
            caption: caption,
          ),
          right: _videoFrameCard(
            title: 'After frame',
            path: job.inputPath,
            caption: caption,
            settings: _settings,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Video preview uses a representative frame; full video export depends on the active video backend.',
          style: _secondaryText(context),
        ),
      ],
    );
  }

  Widget _videoFrameCard({
    required String title,
    required String path,
    required String caption,
    RestorationSettings? settings,
  }) {
    return _previewCard(
      title: title,
      trailing: settings == null ? 'original' : 'adjusted',
      child: SizedBox(
        height: 236,
        width: double.infinity,
        child: VideoFramePreviewTile(
          path: path,
          settings: settings,
          caption: caption,
        ),
      ),
      footer: path,
    );
  }

  Widget _liveBeforeAfterPreview(MediaJob job) {
    return _previewCard(
      title: 'Before / after',
      trailing: 'Live render',
      minHeight: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: _previewAspectRatio(job),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ColoredBox(
                  color: CupertinoColors.black,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          RestoredImagePreview(
                            path: job.inputPath,
                            settings: _settings,
                            lutProfile: _lutProfile,
                          ),
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            width: constraints.maxWidth * _previewSplit,
                            child: ClipRect(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  width: constraints.maxWidth,
                                  height: constraints.maxHeight,
                                  child: Image.file(
                                    File(job.inputPath),
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, _, _) =>
                                        _placeholder(job.kind),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment((_previewSplit * 2) - 1, 0),
                            child: Container(
                              width: 2,
                              color: CupertinoColors.white.withValues(
                                alpha: .86,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 10,
                            top: 10,
                            child: _darkPill('Original'),
                          ),
                          Positioned(
                            right: 10,
                            top: 10,
                            child: _darkPill('Restored'),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            CupertinoSlider(
              value: _previewSplit,
              min: 0,
              max: 1,
              onChanged: (value) => setState(() => _previewSplit = value),
            ),
          ],
        ),
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
    return _noticePanel(
      'Export saved',
      _exportOptions.saveToPhotoLibrary
          ? 'Saved to Photos and AquaRecover Exports.'
          : 'Saved to AquaRecover Exports as ${p.basename(output)}.',
    );
  }

  Widget _batchExportReviewPanel() {
    final complete = _jobs
        .where((job) => job.status == JobStatus.complete)
        .length;
    final failed = _jobs.where((job) => job.status == JobStatus.failed).length;
    final pending = _jobs.length - complete - failed;
    return _sectionBox(
      child: Row(
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
                  '$pending pending - $complete complete${failed == 0 ? '' : ' - $failed failed'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _secondaryText(context),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            minimumSize: Size.zero,
            onPressed: _busy ? null : _clearCompleted,
            child: const Text('Clear'),
          ),
          CupertinoButton.filled(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            minimumSize: Size.zero,
            onPressed: _busy ? null : _processQueue,
            child: const Text('Export all'),
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

  Widget _presetSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('One-tap correction', style: _panelTitle())),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: _busy ? null : _resetSettings,
              child: const Text('Reset'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Balanced underwater correction with adjustable strength.',
          style: _secondaryText(context),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: CupertinoButton.filled(
                onPressed: _busy
                    ? null
                    : () => setState(
                        () => _settings = RestorationPreset.auto.settings,
                      ),
                child: const Text('Auto Fix'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: CupertinoButton(
                onPressed: _busy
                    ? null
                    : () => setState(
                        () => _compareMode =
                            _compareMode == EditorCompareMode.split
                            ? EditorCompareMode.edited
                            : EditorCompareMode.split,
                      ),
                child: Text(
                  _compareMode == EditorCompareMode.split
                      ? 'Edited view'
                      : 'Before / after',
                ),
              ),
            ),
          ],
        ),
        SettingSlider(
          label: 'Color correction',
          value: _settings.recovery,
          min: 0,
          max: 1.25,
          divisions: 25,
          format: (value) => '${(value * 100).round()}%',
          onChanged: _busy
              ? null
              : (value) => setState(
                  () => _settings = _settings.asPro(recovery: value),
                ),
        ),
        _panelDivider(),
        Text('Looks', style: _panelTitle()),
        const SizedBox(height: 4),
        Text(_settings.preset.help, style: _secondaryText(context)),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final preset in editorPresetChoices) ...[
                _choicePill(
                  label: preset.label,
                  selected: _settings.preset == preset,
                  onPressed: _busy
                      ? null
                      : () => setState(() => _settings = preset.settings),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _videoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Video timing', style: _panelTitle()),
        const SizedBox(height: 4),
        Text(
          'Frame preview updates with the same color settings; full video export depends on the backend.',
          style: _secondaryText(context),
        ),
        const SizedBox(height: 8),
        _switchRow(
          title: 'Trim video',
          value: _trimEnabled,
          onChanged: (v) => setState(() => _trimEnabled = v),
        ),
        Row(
          children: [
            Expanded(
              child: _numberField(
                label: 'Start seconds',
                controller: _trimStartController,
                enabled: _trimEnabled,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _numberField(
                label: 'End seconds',
                controller: _trimEndController,
                enabled: _trimEnabled,
                placeholder: 'Optional',
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

  Widget _lutSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LUT', style: _panelTitle()),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final profile in LutProfile.builtIns)
              _choicePill(
                label: profile.name,
                selected: _lutProfile.kind == profile.kind,
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

  Widget _exportOptionsSection() {
    return _sectionBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Options', 'Format and privacy'),
          const SizedBox(height: 8),
          CupertinoSlidingSegmentedControl<ExportPreset>(
            groupValue: _exportPreset,
            children: {
              for (final preset in ExportPreset.values)
                preset: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(preset.label),
                ),
            },
            onValueChanged: (value) {
              if (value != null) _applyExportPreset(value);
            },
          ),
          const SizedBox(height: 8),
          CupertinoSlidingSegmentedControl<ImageOutputFormat>(
            groupValue: _exportOptions.imageFormat,
            children: const {
              ImageOutputFormat.jpeg: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('JPEG'),
              ),
              ImageOutputFormat.png: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('PNG'),
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
          SettingSlider(
            label: 'JPEG quality',
            value: _settings.jpegQuality.toDouble(),
            min: 70,
            max: 100,
            divisions: 30,
            format: (v) => v.round().toString(),
            onChanged: (v) => setState(
              () => _settings = _settings.asPro(jpegQuality: v.round()),
            ),
          ),
          _switchRow(
            title: 'Strip metadata',
            value: _exportOptions.stripMetadata,
            onChanged: (v) => setState(
              () => _exportOptions = _exportOptions.copyWith(stripMetadata: v),
            ),
          ),
          _switchRow(
            title: 'Save exports to Photos',
            value: _exportOptions.saveToPhotoLibrary,
            onChanged: (v) => setState(
              () => _exportOptions = _exportOptions.copyWith(
                saveToPhotoLibrary: v,
              ),
            ),
          ),
          _switchRow(
            title: 'Keep video audio',
            value: _exportOptions.keepAudio,
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
              Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      onPressed: _busy ? null : _clearCompleted,
                      child: const Text('Clear completed'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: CupertinoButton(
                      onPressed: (_jobs.isEmpty || _busy)
                          ? null
                          : _processQueue,
                      child: const Text('Export queue'),
                    ),
                  ),
                ],
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
          if (_busy)
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _cancelProcessing,
              child: const Text('Cancel'),
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
    final paths = await showCupertinoModalPopup<List<String>>(
      context: context,
      builder: (_) => PhotoLibrarySheet(service: _photoLibraryService),
    );
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
    final next = <MediaJob>[];
    var skipped = 0;
    for (var i = 0; i < paths.length; i++) {
      try {
        final metadata = await _inspectionService.inspect(paths[i]);
        next.add(
          MediaJob(
            id: '${now}_$i',
            inputPath: metadata.path,
            kind: metadata.kind,
            displayName: metadata.fileName,
            source: source,
            metadata: metadata,
          ),
        );
      } on Object {
        skipped++;
      }
    }
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
      _step = EditorWorkflowStep.edit;
      _selectedToolGroup = EditorToolGroup.presets;
      _toolPanelOpen = true;
      _compareMode = EditorCompareMode.edited;
      _busy = false;
      _status =
          'Imported ${next.length} item${next.length == 1 ? '' : 's'}${skipped == 0 ? '' : ', skipped $skipped unsupported'} and opened the editor.';
    });
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
      _status = 'Exporting queue...';
    });
    for (var i = 0; i < _jobs.length; i++) {
      if (!mounted || _cancelRequested) break;
      if (_jobs[i].status == JobStatus.complete) continue;
      await _processJob(i, partOfBatch: true);
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _status = _cancelRequested
            ? 'Queue cancelled.'
            : 'Queue export finished.';
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
      await _sidecarService.write(
        inputPath: job.inputPath,
        outputPath: output,
        settings: _settings,
        exportOptions: _exportOptions,
        lutProfile: _lutProfile,
        trim: trim,
        rawVideoDescriptor: rawDescriptor,
      );
      if (_exportOptions.saveToPhotoLibrary) {
        await _photoLibraryService.saveExport(output, job.kind);
      }
      if (!mounted) return;
      setState(() {
        _updateJob(
          index,
          (old) => old.copyWith(
            status: JobStatus.complete,
            outputPath: output,
            progress: 1,
            clearError: true,
          ),
        );
        _step = EditorWorkflowStep.export;
        _status = 'Exported ${p.basename(output)} with sidecar.';
      });
    } on Object catch (error) {
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
      );
    }
    return _imageService.restoreFile(
      inputPath,
      _settings,
      exportOptions: _exportOptions,
      lutProfile: _lutProfile,
    );
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

  void _resetSettings() =>
      setState(() => _settings = RestorationPreset.auto.settings);

  void _cancelProcessing() {
    _cancelRequested = true;
    _videoService.cancelAll();
    setState(() => _status = 'Cancel requested.');
  }

  void _applyExportPreset(ExportPreset preset) {
    setState(() {
      _exportPreset = preset;
      _exportOptions = preset.options.copyWith(
        saveToPhotoLibrary: _exportOptions.saveToPhotoLibrary,
      );
      _settings = _settings.copyWith(jpegQuality: preset.jpegQuality);
    });
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

  void _showAbout() {
    showCupertinoDialog<void>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('AquaRecover'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'On-device underwater color recovery for photos, RAW stills, videos, LUTs, and local exports.',
          ),
        ),
        actions: [
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
  }) {
    return CupertinoButton(
      minimumSize: Size.zero,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: selected
          ? CupertinoTheme.of(context).primaryColor.withValues(alpha: .16)
          : CupertinoDynamicColor.resolve(
              CupertinoColors.systemBackground,
              context,
            ),
      borderRadius: BorderRadius.circular(99),
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          color: selected
              ? CupertinoTheme.of(context).primaryColor
              : CupertinoDynamicColor.resolve(CupertinoColors.label, context),
        ),
      ),
    );
  }

  Widget _pill(String label) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoTheme.of(context).primaryColor.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: CupertinoTheme.of(context).primaryColor.withValues(alpha: .28),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: CupertinoTheme.of(context).primaryColor,
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
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: CupertinoTheme.of(
                context,
              ).textTheme.textStyle.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          CupertinoSwitch(value: value, onChanged: _busy ? null : onChanged),
        ],
      ),
    );
  }

  Widget _numberField({
    required String label,
    required TextEditingController controller,
    required bool enabled,
    String? placeholder,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _secondaryText(context)),
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

  TextStyle _panelTitle() {
    return CupertinoTheme.of(
      context,
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
