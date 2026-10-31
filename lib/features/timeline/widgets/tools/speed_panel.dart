import 'package:flutter/cupertino.dart';

import '../../../../core/timeline/timeline_project.dart';
import '../../timeline_controller.dart';
import '../../timeline_theme.dart';
import 'tool_controls.dart';
import '../../../../shared/widgets/app_tooltip.dart';
import '../../../../l10n/l10n.dart';

/// Speed of the selected video clip or video overlay: 0.25×–4× with detents
/// at the common speeds, evenly spaced so slow motion is as easy to set as
/// fast forward.
class SpeedPanel extends StatefulWidget {
  const SpeedPanel({super.key, required this.controller});

  final TimelineController controller;

  /// Slider stops, one segment apart each.
  static const detents = [0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0];

  /// Slider position (0…6) of [speed].
  static double positionOf(double speed) {
    final s = TimelineSpeed.clamp(speed);
    for (var i = 0; i < detents.length - 1; i++) {
      if (s <= detents[i + 1]) {
        return i + (s - detents[i]) / (detents[i + 1] - detents[i]);
      }
    }
    return detents.length - 1.0;
  }

  /// Speed at slider [position], snapped onto a detent when close.
  static double speedAt(double position) {
    final p = position.clamp(0.0, detents.length - 1.0);
    final nearest = p.roundToDouble();
    if ((p - nearest).abs() < .12) return detents[nearest.toInt()];
    final i = p.floor().clamp(0, detents.length - 2);
    final t = p - i;
    final value = detents[i] + (detents[i + 1] - detents[i]) * t;
    return (value * 20).roundToDouble() / 20;
  }

  @override
  State<SpeedPanel> createState() => _SpeedPanelState();
}

class _SpeedPanelState extends State<SpeedPanel> {
  TimelineController get _controller => widget.controller;

  ({double speed, double sourceSpan, double duration})? get _target {
    final clip = _controller.selectedClip;
    if (clip != null && clip.isVideo) {
      return (
        speed: clip.playbackSpeed,
        sourceSpan: clip.sourceSpan,
        duration: clip.duration,
      );
    }
    final overlay = _controller.selectedOverlay;
    if (overlay != null && overlay.isVideo) {
      return (
        speed: overlay.playbackSpeed,
        sourceSpan: overlay.sourceSpan,
        duration: overlay.duration,
      );
    }
    return null;
  }

  void _set(double speed) {
    final current = _target?.speed;
    if (current == speed) return;
    if (SpeedPanel.detents.contains(speed)) snapHaptic();
    _controller.setSpeed(speed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final target = _target;
    final header = ToolHeader(
      title: l10n.toolSpeed,
      trailing: ToolTextButton(
        label: l10n.reset,
        onPressed: target == null || target.speed == 1 ? null : () => _set(1),
      ),
    );
    if (target == null) {
      return ToolPanelBody(
        header: header,
        children: [ToolEmptyNote(l10n.selectVideoForSpeed)],
      );
    }
    final label = _speedText(l10n, target.speed);
    return ToolPanelBody(
      header: header,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              label,
              key: const Key('timeline_speed_value'),
              style: const TextStyle(
                color: TimelineColors.text,
                fontSize: 28,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            Flexible(
              flex: 4,
              child: Text(
                '${formatTimecode(target.sourceSpan)} → '
                '${formatTimecode(target.duration)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: TimelineColors.secondaryText,
                  fontSize: 13,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        Semantics(
          label: l10n.toolSpeed,
          value: label,
          increasedValue: _speedText(
            l10n,
            SpeedPanel.speedAt(SpeedPanel.positionOf(target.speed) + 1),
          ),
          decreasedValue: _speedText(
            l10n,
            SpeedPanel.speedAt(SpeedPanel.positionOf(target.speed) - 1),
          ),
          child: SizedBox(
            height: 44,
            child: CupertinoSlider(
              key: const Key('timeline_speed_slider'),
              value: SpeedPanel.positionOf(target.speed),
              min: 0,
              max: SpeedPanel.detents.length - 1.0,
              activeColor: TimelineColors.text,
              onChangeStart: (_) => _controller.beginGesture(),
              onChanged: (p) => _set(SpeedPanel.speedAt(p)),
              onChangeEnd: (_) => _controller.endGesture(),
            ),
          ),
        ),
        ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final d in SpeedPanel.detents)
                  Text(
                    _speedText(l10n, d),
                    style: TextStyle(
                      color: d == target.speed
                          ? TimelineColors.text
                          : TimelineColors.secondaryText,
                      fontWeight: d == target.speed
                          ? FontWeight.w600
                          : FontWeight.w400,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.speedPitchNote,
          style: const TextStyle(
            color: TimelineColors.secondaryText,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  /// "1.5×", with the app language's decimal separator.
  static String _speedText(AppLocalizations l10n, double speed) =>
      l10n.speedValue(l10n.compactDecimal(speed));
}

/// How long the selected photo, photo overlay, or title stays on screen.
class DurationPanel extends StatelessWidget {
  const DurationPanel({super.key, required this.controller});

  final TimelineController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final clip = controller.selectedClip;
    final overlay = controller.selectedOverlay;
    final seconds = clip != null && !clip.isVideo
        ? clip.stillSeconds
        : overlay != null && !overlay.isVideo
        ? overlay.stillSeconds
        : null;
    Widget step(IconData icon, double delta, String label) => AppTooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(
            kMinInteractiveDimensionCupertino,
            kMinInteractiveDimensionCupertino,
          ),
          onPressed: seconds == null
              ? null
              : () => controller.setStillSeconds(seconds + delta),
          child: Icon(icon, size: 20, color: TimelineColors.text),
        ),
      ),
    );
    return ToolPanelBody(
      header: ToolHeader(
        title: l10n.toolDuration,
        subtitle: selectionName(context.l10n, controller),
      ),
      children: [
        if (seconds == null)
          ToolEmptyNote(l10n.selectPhotoForDuration)
        else ...[
          ToolSlider(
            controller: controller,
            label: l10n.lengthOnScreen,
            value: seconds.clamp(0.5, 15).toDouble(),
            min: 0.5,
            max: 15,
            divisions: 29,
            valueLabel: secondsLabel(l10n, seconds),
            onChanged: controller.setStillSeconds,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              step(CupertinoIcons.minus, -0.5, l10n.halfSecondShorter),
              const SizedBox(width: 24),
              step(CupertinoIcons.plus, 0.5, l10n.halfSecondLonger),
            ],
          ),
        ],
      ],
    );
  }
}
