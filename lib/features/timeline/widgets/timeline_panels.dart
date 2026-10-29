import 'package:flutter/cupertino.dart';

import '../../../core/models/lut_profile.dart';
import '../../../core/models/restoration_settings.dart';
import '../../../core/timeline/timeline_project.dart';
import '../../../core/platform/share_service.dart';
import '../../../shared/widgets/app_tooltip.dart';
import '../../editor/widgets/precision_wheel.dart';
import '../timeline_controller.dart';
import '../timeline_theme.dart';
import 'tools/tool_controls.dart';
import '../../../shared/widgets/mouse_drag_scroll.dart';

/// One adjustable grade parameter on the Color page.
class GradeControl {
  const GradeControl(
    this.label,
    this.min,
    this.max,
    this.read,
    this.write, {
    this.divisions = 100,
  });

  final String label;
  final double min;
  final double max;
  final int divisions;
  final double Function(RestorationSettings s) read;
  final RestorationSettings Function(RestorationSettings s, double v) write;

  static final all = <GradeControl>[
    GradeControl(
      'Strength',
      0,
      1,
      (s) => s.presetStrength,
      (s, v) => s.preset
          .settingsAtStrength(v)
          .copyWith(temperature: s.temperature, tint: s.tint),
    ),
    GradeControl(
      'Recovery',
      0,
      2,
      (s) => s.recovery,
      (s, v) => s.copyWith(recovery: v),
    ),
    GradeControl(
      'Red',
      0,
      2,
      (s) => s.redRecovery,
      (s, v) => s.copyWith(redRecovery: v),
    ),
    GradeControl(
      'Balance',
      0,
      1,
      (s) => s.autoWhiteBalance,
      (s, v) => s.copyWith(autoWhiteBalance: v),
    ),
    GradeControl(
      'Temp',
      -1,
      1,
      (s) => s.temperature,
      (s, v) => s.copyWith(temperature: v),
    ),
    GradeControl('Tint', -1, 1, (s) => s.tint, (s, v) => s.copyWith(tint: v)),
    GradeControl(
      'Exposure',
      -1,
      1,
      (s) => s.exposure,
      (s, v) => s.copyWith(exposure: v),
    ),
    GradeControl(
      'Contrast',
      .7,
      1.6,
      (s) => s.contrast,
      (s, v) => s.copyWith(contrast: v),
      divisions: 90,
    ),
    GradeControl(
      'Saturation',
      0,
      2,
      (s) => s.saturation,
      (s, v) => s.copyWith(saturation: v),
    ),
    GradeControl(
      'Haze',
      0,
      1,
      (s) => s.hazeReduction,
      (s, v) => s.copyWith(hazeReduction: v),
    ),
    GradeControl(
      'Shadows',
      -1,
      1,
      (s) => s.shadows,
      (s, v) => s.copyWith(shadows: v),
    ),
    GradeControl(
      'Highlights',
      -1,
      1,
      (s) => s.highlights,
      (s, v) => s.copyWith(highlights: v),
    ),
    GradeControl('Hue', -1, 1, (s) => s.hue, (s, v) => s.copyWith(hue: v)),
  ];
}

/// Color page: preset, one wheel for the chosen parameter, and a look.
class ColorPanel extends StatefulWidget {
  const ColorPanel({super.key, required this.controller});

  final TimelineController controller;

  @override
  State<ColorPanel> createState() => _ColorPanelState();
}

class _ColorPanelState extends State<ColorPanel> {
  int _control = 0;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final clip = controller.selectedClip;
    final overlay = controller.selectedOverlay;
    final gradeable =
        clip != null || (overlay != null && overlay.title == null);
    final header = ToolHeader(
      title: 'Color',
      subtitle: selectionName(controller),
      // Matching every clip to this grade is the quick way to even out a
      // whole dive.
      trailing: clip == null
          ? null
          : ToolTextButton(
              key: const Key('timeline_grade_all'),
              label: 'Apply to All',
              onPressed: controller.project.clips.length > 1
                  ? controller.applyGradeToAll
                  : null,
            ),
    );
    if (!gradeable) {
      return Column(
        children: [
          header,
          const Expanded(
            child: ToolEmptyNote('Select a clip or overlay to grade it.'),
          ),
        ],
      );
    }
    // An overlay without a grade of its own shows its original colours.
    final RestorationSettings? own = clip?.grade ?? overlay!.grade;
    final grade = own ?? RestorationPreset.none.settings;
    final look = clip?.look ?? overlay!.look;
    final id = clip?.id ?? overlay!.id;
    final control = GradeControl.all[_control];
    return ToolPanelBody(
      header: header,
      children: [
        _ChipRow(
          children: [
            for (final preset in RestorationPreset.values)
              _Chip(
                label: preset.label,
                selected: own != null
                    ? grade.preset == preset
                    : preset == RestorationPreset.none,
                onTap: () => controller.setGrade(
                  overlay != null && preset == RestorationPreset.none
                      ? null
                      : preset.settingsAtStrength(
                          grade.preset == preset ? grade.presetStrength : 1,
                        ),
                ),
              ),
          ],
        ),
        _ChipRow(
          children: [
            for (var i = 0; i < GradeControl.all.length; i++)
              _Chip(
                label: GradeControl.all[i].label,
                selected: i == _control,
                outlined: true,
                onTap: () => setState(() => _control = i),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: CupertinoTheme(
            data: const CupertinoThemeData(brightness: Brightness.dark),
            // One drag on the wheel is one undo step.
            child: Listener(
              onPointerDown: (_) => controller.beginGesture(),
              onPointerUp: (_) => controller.endGesture(),
              onPointerCancel: (_) => controller.endGesture(),
              child: PrecisionWheel(
                key: ValueKey('wheel-$id-${control.label}'),
                value: control.read(grade).clamp(control.min, control.max),
                min: control.min,
                max: control.max,
                divisions: control.divisions,
                semanticLabel: control.label,
                valueFormatter: (v) => v.toStringAsFixed(2),
                onChanged: (v) => controller.setGrade(control.write(grade, v)),
              ),
            ),
          ),
        ),
        _ChipRow(
          children: [
            for (final item in LutProfile.builtIns)
              _Chip(
                label: item.name,
                selected: look.kind == item.kind,
                onTap: () => controller.setLook(item),
              ),
          ],
        ),
      ],
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: MouseDragScroll(
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          children: [
            for (final child in children)
              Padding(padding: const EdgeInsets.only(right: 6), child: child),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.outlined = false,
  });

  final String label;
  final bool selected;
  final bool outlined;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Looks pick like the Presets chips; parameters select like the
    // photo editor's choice pills.
    final fill = selected
        ? (outlined
              ? TimelineColors.accent.withValues(alpha: .18)
              : CupertinoColors.activeBlue)
        : TimelineColors.fill;
    final foreground = selected && outlined
        ? TimelineColors.accent
        : TimelineColors.text;
    return Semantics(
      button: true,
      selected: selected,
      // A compact capsule inside the 44 pt hit region.
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(
          kMinInteractiveDimensionCupertino,
          kMinInteractiveDimensionCupertino,
        ),
        onPressed: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            color: fill,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Export page: output format and the export button.
class DeliverPanel extends StatelessWidget {
  const DeliverPanel({
    super.key,
    required this.controller,
    required this.rendering,
    required this.progress,
    required this.outputPath,
    required this.onRender,
    required this.onCancel,
    required this.onSaveToPhotos,
    required this.onOpenLibrary,
    this.onShare,
    this.backendNote,
  });

  final TimelineController controller;
  final bool rendering;
  final double progress;
  final String? outputPath;
  final VoidCallback? onRender;
  final VoidCallback onCancel;
  final VoidCallback? onSaveToPhotos;
  final VoidCallback onOpenLibrary;

  /// Opens the system share sheet for the rendered movie, anchored to the
  /// given rectangle. Null where the device has no file share sheet.
  final ValueChanged<Rect?>? onShare;
  final String? backendNote;

  static const _frameRates = [24, 30, 60];
  static const _fadeSeconds = [0.3, 0.6, 1.0, 1.5];

  static Widget _pill({
    Key? key,
    required VoidCallback onPressed,
    required Widget child,
  }) => CupertinoButton(
    key: key,
    color: TimelineColors.fill,
    borderRadius: BorderRadius.circular(99),
    padding: const EdgeInsets.symmetric(vertical: 12),
    onPressed: onPressed,
    child: child,
  );

  /// Save to Photos, Share and Open exports for a finished movie. Three
  /// pills do not fit a phone's width side by side, so Open exports moves
  /// to its own row when both delivery actions are offered.
  List<Widget> _finishedActions() {
    final save = onSaveToPhotos;
    final share = onShare;
    final deliver = <Widget>[
      if (save != null)
        _pill(
          onPressed: save,
          child: const Text(
            'Save to Photos',
            style: TextStyle(color: TimelineColors.text),
          ),
        ),
      if (share != null)
        AppTooltip(
          message: 'Share the movie',
          child: Builder(
            builder: (buttonContext) => _pill(
              key: const Key('timeline_share_movie'),
              onPressed: () => share(shareOriginOf(buttonContext)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.share,
                    size: 18,
                    color: TimelineColors.text,
                  ),
                  SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      'Share',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: TimelineColors.text),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ];
    final library = _pill(
      onPressed: onOpenLibrary,
      child: const Text(
        'Open exports',
        style: TextStyle(color: TimelineColors.text),
      ),
    );
    Widget row(List<Widget> buttons) => Row(
      children: [
        for (final (index, button) in buttons.indexed) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(child: button),
        ],
      ],
    );
    if (deliver.length < 2) {
      return [
        row([...deliver, library]),
      ];
    }
    return [
      row(deliver),
      const SizedBox(height: 8),
      row([library]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final project = controller.project;
    final (:width, :height) = project.outputSize;
    // The settings stay visible but read as disabled while rendering.
    final thumb = CupertinoColors.activeBlue.withValues(
      alpha: rendering ? .38 : 1,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            '$width × $height · ${formatTimecode(project.duration)} · '
            'H.264 MP4${backendNote == null ? '' : ' · $backendNote'}',
            style: const TextStyle(
              color: TimelineColors.secondaryText,
              fontSize: 12,
            ),
          ),
        ),
        if (rendering) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(height: 6, child: LinearProgress(value: progress)),
          ),
          const SizedBox(height: 8),
          CupertinoButton(
            key: const Key('timeline_cancel_render'),
            color: TimelineColors.fill,
            borderRadius: BorderRadius.circular(99),
            onPressed: onCancel,
            child: Text(
              'Cancel · ${(progress * 100).round()}%',
              style: const TextStyle(color: TimelineColors.text),
            ),
          ),
        ] else
          CupertinoButton(
            key: const Key('timeline_render'),
            color: CupertinoColors.activeBlue,
            borderRadius: BorderRadius.circular(99),
            onPressed: onRender,
            child: const Text(
              'Export movie',
              style: TextStyle(
                color: CupertinoColors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (outputPath != null && !rendering) ...[
          const SizedBox(height: 10),
          ..._finishedActions(),
        ],
        const SizedBox(height: 16),
        _SettingRow(
          label: 'Frame',
          child: CupertinoSlidingSegmentedControl<TimelineAspect>(
            groupValue: project.aspect,
            backgroundColor: TimelineColors.fill,
            thumbColor: thumb,
            children: {
              for (final aspect in TimelineAspect.values)
                aspect: _segmentText(
                  '${aspect.widthRatio}:${aspect.heightRatio}',
                  enabled: !rendering,
                ),
            },
            disabledChildren: rendering
                ? TimelineAspect.values.toSet()
                : const {},
            onValueChanged: (v) {
              if (v != null) {
                controller.updateProject((p) => p.copyWith(aspect: v));
              }
            },
          ),
        ),
        _SettingRow(
          label: 'Quality',
          child: CupertinoSlidingSegmentedControl<TimelineQuality>(
            groupValue: project.quality,
            backgroundColor: TimelineColors.fill,
            thumbColor: thumb,
            children: {
              for (final quality in TimelineQuality.values)
                quality: _segmentText(quality.label, enabled: !rendering),
            },
            disabledChildren: rendering
                ? TimelineQuality.values.toSet()
                : const {},
            onValueChanged: (v) {
              if (v != null) {
                controller.updateProject((p) => p.copyWith(quality: v));
              }
            },
          ),
        ),
        _SettingRow(
          label: 'Frame rate',
          child: CupertinoSlidingSegmentedControl<int>(
            groupValue: project.frameRate,
            backgroundColor: TimelineColors.fill,
            thumbColor: thumb,
            children: {
              for (final fps in _frameRates)
                fps: _segmentText('$fps', enabled: !rendering),
            },
            disabledChildren: rendering ? _frameRates.toSet() : const {},
            onValueChanged: (v) {
              if (v != null) {
                controller.updateProject((p) => p.copyWith(frameRate: v));
              }
            },
          ),
        ),
        _SettingRow(
          label: 'Fades',
          child: CupertinoSlidingSegmentedControl<double>(
            groupValue: project.transitionSeconds,
            backgroundColor: TimelineColors.fill,
            thumbColor: thumb,
            children: {
              for (final s in _fadeSeconds)
                s: _segmentText('${s}s', enabled: !rendering),
            },
            disabledChildren: rendering ? _fadeSeconds.toSet() : const {},
            onValueChanged: (v) {
              if (v != null) {
                controller.updateProject(
                  (p) => p.copyWith(transitionSeconds: v),
                );
              }
            },
          ),
        ),
      ],
    );
  }

  /// A segment label. Its explicit color overrides the control's own
  /// disabled style, so a disabled label dims itself.
  /// Shrinks a little in the narrow inspector of small iPad and Mac
  /// windows instead of breaking "16:9" or "1080p" over two lines.
  static Widget _segmentText(String text, {required bool enabled}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          color: TimelineColors.text.withValues(alpha: enabled ? 1 : .38),
          fontSize: 13,
        ),
      ),
    ),
  );
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: const TextStyle(
                color: TimelineColors.secondaryText,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A minimal determinate progress bar in the workspace colours.
class LinearProgress extends StatelessWidget {
  const LinearProgress({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: TimelineColors.stroke),
        FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value.clamp(0.0, 1.0),
          child: const ColoredBox(color: CupertinoColors.activeBlue),
        ),
      ],
    );
  }
}
