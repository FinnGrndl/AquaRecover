import 'package:flutter/cupertino.dart';

import '../../timeline_controller.dart';
import 'tool_controls.dart';

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
    return ToolPanelBody(
      header: ToolHeader(
        title: 'Volume',
        subtitle: selectionName(controller),
        trailing: ToolTextButton(
          label: 'Reset',
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
          const ToolEmptyNote('Photos and titles have no sound.')
        else ...[
          ToolSlider(
            key: const Key('timeline_volume_slider'),
            controller: controller,
            label: 'Level',
            value: state.muted ? 0 : state.volume,
            min: 0,
            max: 1,
            valueLabel: state.muted ? 'Muted' : percentLabel(state.volume),
            onChanged: controller.setVolume,
          ),
          ToolRow(
            label: 'Mute',
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
