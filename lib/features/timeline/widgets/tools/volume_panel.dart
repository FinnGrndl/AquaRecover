import 'package:flutter/cupertino.dart';

import '../../timeline_controller.dart';
import 'tool_controls.dart';
import '../../../../l10n/l10n.dart';

/// Level and mute of the selected clip, video overlay, or sound.
class VolumePanel extends StatelessWidget {
  const VolumePanel({super.key, required this.controller});

  final TimelineController controller;

  @override
  Widget build(BuildContext context) {
    final clip = controller.selectedClip;
    final overlay = controller.selectedOverlay;
    final audio = controller.selectedAudio;
    final ({double volume, bool muted})? state = clip != null && clip.isVideo
        ? (volume: clip.volume, muted: clip.muted)
        : overlay != null && overlay.isVideo
        ? (volume: overlay.volume, muted: overlay.muted)
        : audio != null
        ? (volume: audio.volume, muted: audio.volume <= 0)
        : null;
    final l10n = context.l10n;
    return ToolPanelBody(
      header: ToolHeader(
        title: l10n.toolVolume,
        subtitle: selectionName(context.l10n, controller),
        trailing: ToolTextButton(
          label: l10n.reset,
          onPressed: state == null || (state.volume == 1 && !state.muted)
              ? null
              : () {
                  controller.beginGesture();
                  controller.setMuted(false);
                  controller.setVolume(1);
                  controller.endGesture();
                },
        ),
      ),
      children: [
        if (state == null)
          ToolEmptyNote(l10n.noSoundNote)
        else ...[
          ToolSlider(
            key: const Key('timeline_volume_slider'),
            controller: controller,
            label: l10n.volumeLevel,
            value: state.muted ? 0 : state.volume,
            min: 0,
            max: 1,
            valueLabel: state.muted ? l10n.muted : percentLabel(state.volume),
            onChanged: controller.setVolume,
          ),
          ToolRow(
            label: l10n.mute,
            child: CupertinoSwitch(
              key: const Key('timeline_mute_switch'),
              value: state.muted || state.volume <= 0,
              onChanged: controller.setMuted,
            ),
          ),
        ],
      ],
    );
  }
}
