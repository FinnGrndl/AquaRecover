import 'dart:io';

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
import 'widgets/gpu_preview_filter.dart';
import 'widgets/photo_library_sheet.dart';
import 'widgets/raw_video_dialog.dart';
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
  bool _busy = false;
  bool _cancelRequested = false;
  String? _status = 'Ready.';

  MediaJob? get _selectedJob {
    if (_jobs.isEmpty) return null;
    return _jobs[_selectedIndex.clamp(0, _jobs.length - 1).toInt()];
  }

  EditorWorkflowState get _workflowState {
    return EditorWorkflowState(
      step: _step,
      hasSelection: _selectedJob != null,
      busy: _busy,
    );
  }

  @override
  void dispose() {
    _trimStartController.dispose();
    _trimEndController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                        const SizedBox(height: 12),
                        _statusPanel(),
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

  Widget _workflowPane({required bool wide}) {
    final content = GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _workflowTitle(),
          const SizedBox(height: 14),
          _workflowStepper(),
          const SizedBox(height: 18),
          _stepBody(wide: wide),
        ],
      ),
    );
    if (!wide) return content;
    return CupertinoScrollbar(
      child: ListView(padding: const EdgeInsets.all(20), children: [content]),
    );
  }

  Widget _sidePane() {
    return CupertinoScrollbar(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 20, 20, 24),
        children: [_statusPanel(), const SizedBox(height: 12), _queueSection()],
      ),
    );
  }

  Widget _workflowTitle() {
    return Row(
      children: [
        const Icon(CupertinoIcons.drop_fill, color: CupertinoColors.activeBlue),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Import. Edit. Export.',
            style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
          ),
        ),
      ],
    );
  }

  Widget _workflowStepper() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final children = [
          for (final step in EditorWorkflowStep.values)
            _stepButton(step, compact: compact),
        ];
        return compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              )
            : Row(
                children: children
                    .map((child) => Expanded(child: child))
                    .toList(),
              );
      },
    );
  }

  Widget _stepButton(EditorWorkflowStep step, {required bool compact}) {
    final state = _workflowState;
    final selected = step == _step;
    final enabled = state.canEnter(step);
    final color = selected
        ? CupertinoTheme.of(context).primaryColor.withValues(alpha: 0.16)
        : CupertinoDynamicColor.resolve(
            CupertinoColors.secondarySystemGroupedBackground,
            context,
          );
    final borderColor = selected
        ? CupertinoTheme.of(context).primaryColor.withValues(alpha: 0.50)
        : CupertinoDynamicColor.resolve(CupertinoColors.separator, context);
    final button = CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      minimumSize: Size.zero,
      borderRadius: BorderRadius.circular(14),
      color: enabled ? color : color.withValues(alpha: 0.48),
      onPressed: enabled ? () => setState(() => _step = step) : null,
      child: Row(
        mainAxisAlignment: compact
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          _stepBadge(step, selected),
          const SizedBox(width: 8),
          Flexible(child: Text(step.label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
    return Container(
      margin: EdgeInsets.only(right: compact ? 0 : 8, bottom: compact ? 8 : 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: button,
    );
  }

  Widget _stepBadge(EditorWorkflowStep step, bool selected) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected
            ? CupertinoTheme.of(context).primaryColor
            : CupertinoDynamicColor.resolve(
                CupertinoColors.systemGrey4,
                context,
              ),
      ),
      child: SizedBox(
        width: 24,
        height: 24,
        child: Center(
          child: Text(
            step.shortLabel,
            style: TextStyle(
              color: selected
                  ? CupertinoColors.white
                  : CupertinoDynamicColor.resolve(
                      CupertinoColors.label,
                      context,
                    ),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
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
        _sectionHeader('Import', 'Files or Photos'),
        const SizedBox(height: 12),
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
          ],
        ),
        const SizedBox(height: 16),
        if (job == null) _emptyImportState() else _importSummary(job),
        if (showQueue && _jobs.isNotEmpty) ...[
          const SizedBox(height: 16),
          _queueSection(compact: true),
        ],
        const SizedBox(height: 16),
        _navigationRow(nextLabel: 'Edit selected'),
      ],
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
        final reservedPreview = compact ? 220.0 : 280.0;
        final reservedChrome = compact ? 168.0 : 176.0;
        final availablePanelHeight =
            constraints.maxHeight - reservedPreview - reservedChrome;
        final panelHeight = availablePanelHeight <= 96
            ? 0.0
            : availablePanelHeight.clamp(
                compact ? 176.0 : 210.0,
                compact ? 270.0 : 340.0,
              );
        final panelOpen = _toolPanelOpen && panelHeight > 0;
        return Padding(
          padding: EdgeInsets.fromLTRB(wide ? 20 : 12, 8, wide ? 20 : 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _editorTopBar(job),
              const SizedBox(height: 10),
              Expanded(
                child: EditorPreviewStage(
                  job: job,
                  settings: _settings,
                  compareMode: _compareMode,
                ),
              ),
              const SizedBox(height: 8),
              EditorToolRail(
                groups: groups,
                selectedGroup: activeGroup,
                panelOpen: panelOpen,
                onSelected: _selectToolGroup,
              ),
              EditorBottomPanel(
                group: activeGroup,
                open: panelOpen,
                height: panelHeight,
                onClose: () => setState(() => _toolPanelOpen = false),
                child: _toolPanelContent(job, activeGroup),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _editorTopBar(MediaJob job) {
    final title = job.displayName ?? p.basename(job.inputPath);
    return Row(
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
              Icon(CupertinoIcons.chevron_left, size: 18),
              SizedBox(width: 4),
              Text('Import'),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: CupertinoTheme.of(
                  context,
                ).textTheme.textStyle.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                '${job.kind.label} - ${job.status.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: _secondaryText(context),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
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

  Widget _exportStep() {
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
        _exportOptionsSection(),
        if (videoUnavailable) ...[
          const SizedBox(height: 12),
          _noticePanel('Video export unavailable', _videoUnavailableMessage),
        ],
        const SizedBox(height: 12),
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

  Widget _selectedMediaHeader(MediaJob job) {
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
          job.displayName ?? p.basename(job.inputPath),
          style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
        ),
        const SizedBox(height: 4),
        Text(
          job.inputPath,
          maxLines: 2,
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
      );
    }
    if (job.kind == MediaKind.photo) {
      return _splitCards(
        left: _mediaCard(title: 'Before', path: job.inputPath, kind: job.kind),
        right: _gpuPreviewCard(job.inputPath, title: 'After preview'),
      );
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

  Widget _gpuPreviewCard(String path, {required String title}) {
    return _previewCard(
      title: title,
      trailing: 'approx',
      child: SizedBox(
        height: 236,
        width: double.infinity,
        child: GpuPreviewFilter(path: path, settings: _settings),
      ),
      footer:
          'Fast preview uses the device renderer. Export uses the local image pipeline.',
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
    return _noticePanel('Export complete', output);
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
            Expanded(child: Text('Looks', style: _panelTitle())),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: _busy ? null : _resetSettings,
              child: const Text('Reset'),
            ),
          ],
        ),
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

  Widget _navigationRow({
    String backLabel = 'Back',
    String nextLabel = 'Next',
  }) {
    final state = _workflowState;
    return Row(
      children: [
        Expanded(
          child: CupertinoButton(
            onPressed: state.canGoBack && !_busy
                ? () => setState(() => _step = state.previous)
                : null,
            child: Text(backLabel),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: CupertinoButton.filled(
            onPressed: state.canGoForward && !_busy
                ? () => setState(() => _step = state.next)
                : null,
            child: Text(nextLabel),
          ),
        ),
      ],
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
      _step = EditorWorkflowStep.import;
      _busy = false;
      _status =
          'Imported ${next.length} item${next.length == 1 ? '' : 's'}${skipped == 0 ? '' : ', skipped $skipped unsupported'}.';
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
        borderRadius: BorderRadius.circular(18),
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
      borderRadius: BorderRadius.circular(18),
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
