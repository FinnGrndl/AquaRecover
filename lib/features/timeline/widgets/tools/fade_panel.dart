import 'package:flutter/cupertino.dart';

import '../../../../core/timeline/timeline_project.dart';
import '../../timeline_controller.dart';
import 'tool_controls.dart';
import '../../../../l10n/timeline_labels.dart';
import '../../../../l10n/l10n.dart';

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
    final l10n = context.l10n;
    return ToolPanelBody(
      header: ToolHeader(
        title: l10n.toolFade,
        subtitle: selectionName(context.l10n, controller),
        trailing: ToolTextButton(
          label: l10n.reset,
          onPressed: fades == null || (fades.fadeIn == 0 && fades.fadeOut == 0)
              ? null
              : () => controller.setFades(fadeIn: 0, fadeOut: 0),
        ),
      ),
      children: [
        if (fades == null)
          ToolEmptyNote(l10n.selectItemToFade)
        else ...[
          ToolSlider(
            key: const Key('timeline_fade_in'),
            controller: controller,
            label: l10n.fadeIn,
            value: fades.fadeIn.clamp(0, maxSeconds).toDouble(),
            min: 0,
            max: maxSeconds,
            divisions: 30,
            valueLabel: secondsLabel(l10n, fades.fadeIn),
            onChanged: (v) => controller.setFades(fadeIn: v),
          ),
          ToolSlider(
            key: const Key('timeline_fade_out'),
            controller: controller,
            label: l10n.fadeOut,
            value: fades.fadeOut.clamp(0, maxSeconds).toDouble(),
            min: 0,
            max: maxSeconds,
            divisions: 30,
            valueLabel: secondsLabel(l10n, fades.fadeOut),
            onChanged: (v) => controller.setFades(fadeOut: v),
          ),
          if (clip != null) ...[
            const SizedBox(height: 6),
            ToolSegmented<FadeColor>(
              label: l10n.fadeColorLabel,
              labelWidth: 56,
              value: clip.fadeColor,
              options: {for (final c in FadeColor.values) c: c.labelIn(l10n)},
              onChanged: controller.setFadeColor,
            ),
          ],
        ],
      ],
    );
  }
}
