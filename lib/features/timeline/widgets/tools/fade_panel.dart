import 'package:flutter/cupertino.dart';

import '../../../../core/timeline/timeline_project.dart';
import '../../timeline_controller.dart';
import 'tool_controls.dart';

/// Fade in and out of the selected item; main clips also pick the colour
/// they fade from and to.
class FadePanel extends StatelessWidget {
  const FadePanel({super.key, required this.controller});

  final TimelineController controller;

  static const maxSeconds = 3.0;

  @override
  Widget build(BuildContext context) {
    final clip = controller.selectedClip;
    final overlay = controller.selectedOverlay;
    final audio = controller.selectedAudio;
    final ({double fadeIn, double fadeOut})? fades = clip != null
        ? (fadeIn: clip.fadeIn, fadeOut: clip.fadeOut)
        : overlay != null
        ? (fadeIn: overlay.fadeIn, fadeOut: overlay.fadeOut)
        : audio != null
        ? (fadeIn: audio.fadeIn, fadeOut: audio.fadeOut)
        : null;
    return ToolPanelBody(
      header: ToolHeader(
        title: 'Fade',
        subtitle: selectionName(controller),
        trailing: ToolTextButton(
          label: 'Reset',
          onPressed: fades == null || (fades.fadeIn == 0 && fades.fadeOut == 0)
              ? null
              : () => controller.setFades(fadeIn: 0, fadeOut: 0),
        ),
      ),
      children: [
        if (fades == null)
          const ToolEmptyNote('Select an item to fade it.')
        else ...[
          ToolSlider(
            key: const Key('timeline_fade_in'),
            controller: controller,
            label: 'Fade in',
            value: fades.fadeIn.clamp(0, maxSeconds).toDouble(),
            min: 0,
            max: maxSeconds,
            divisions: 30,
            valueLabel: secondsLabel(fades.fadeIn),
            onChanged: (v) => controller.setFades(fadeIn: v),
          ),
          ToolSlider(
            key: const Key('timeline_fade_out'),
            controller: controller,
            label: 'Fade out',
            value: fades.fadeOut.clamp(0, maxSeconds).toDouble(),
            min: 0,
            max: maxSeconds,
            divisions: 30,
            valueLabel: secondsLabel(fades.fadeOut),
            onChanged: (v) => controller.setFades(fadeOut: v),
          ),
          if (clip != null) ...[
            const SizedBox(height: 6),
            ToolSegmented<FadeColor>(
              label: 'Color',
              labelWidth: 56,
              value: clip.fadeColor,
              options: {for (final c in FadeColor.values) c: c.label},
              onChanged: controller.setFadeColor,
            ),
          ],
        ],
      ],
    );
  }
}
