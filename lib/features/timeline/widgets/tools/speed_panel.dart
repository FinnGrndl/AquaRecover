import 'package:flutter/cupertino.dart';

import '../../../../core/timeline/timeline_project.dart';
import '../../timeline_controller.dart';
import '../../timeline_theme.dart';
import 'tool_controls.dart';
import '../../../../shared/widgets/app_tooltip.dart';

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
    final target = _target;
    final header = ToolHeader(
      title: 'Speed',
      trailing: ToolTextButton(
        label: 'Reset',
        onPressed: target == null || target.speed == 1 ? null : () => _set(1),
      ),
    );
    if (target == null) {
      return ToolPanelBody(
        header: header,
        children: const [
          ToolEmptyNote('Select a video clip to change its speed.'),
        ],
      );
    }
    final label = '${_speedText(target.speed)}×';
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
          label: 'Speed',
          value: label,
          increasedValue:
              '${_speedText(SpeedPanel.speedAt(SpeedPanel.positionOf(target.speed) + 1))}×',
          decreasedValue:
              '${_speedText(SpeedPanel.speedAt(SpeedPanel.positionOf(target.speed) - 1))}×',
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
                    '${_speedText(d)}×',
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
        const Text(
          'Sound keeps its pitch. Length on the timeline changes with speed.',
          style: TextStyle(color: TimelineColors.secondaryText, fontSize: 12),
        ),
      ],
    );
  }

  static String _speedText(double speed) {
    final text = speed.toStringAsFixed(2);
    return text
        .replaceFirst(RegExp(r'0$'), '')
        .replaceFirst(RegExp(r'\.0$'), '');
  }
}

/// How long the selected photo, photo overlay, or title stays on screen.
class DurationPanel extends StatelessWidget {
  const DurationPanel({super.key, required this.controller});

  final TimelineController controller;

  @override
  Widget build(BuildContext context) {
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
        title: 'Duration',
        subtitle: selectionName(controller),
      ),
      children: [
        if (seconds == null)
          const ToolEmptyNote('Select a photo or title to change its length.')
        else ...[
          ToolSlider(
            controller: controller,
            label: 'Length on screen',
            value: seconds.clamp(0.5, 15).toDouble(),
            min: 0.5,
            max: 15,
            divisions: 29,
            valueLabel: secondsLabel(seconds),
            onChanged: controller.setStillSeconds,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              step(CupertinoIcons.minus, -0.5, 'Half a second shorter'),
              const SizedBox(width: 24),
              step(CupertinoIcons.plus, 0.5, 'Half a second longer'),
            ],
          ),
        ],
      ],
    );
  }
}
