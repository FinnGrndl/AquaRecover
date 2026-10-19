import 'package:flutter/cupertino.dart';

import '../../timeline_controller.dart';
import 'tool_controls.dart';

/// Less frequent actions on the selected main clip, collected like a More
/// menu so the toolbar stays short.
class MorePanel extends StatelessWidget {
  const MorePanel({
    super.key,
    required this.controller,
    required this.onReplace,
    required this.onError,
  });

  final TimelineController controller;
  final VoidCallback onReplace;
  final void Function(String title, String message) onError;

  @override
  Widget build(BuildContext context) {
    final clip = controller.selectedClip;
    final index = controller.selectedIndex;
    final count = controller.project.clips.length;
    return ToolPanelBody(
      header: ToolHeader(title: 'More', subtitle: selectionName(controller)),
      children: [
        ToolActionRow(
          key: const Key('timeline_move_earlier'),
          icon: CupertinoIcons.chevron_left_2,
          label: 'Move Earlier',
          onPressed: index > 0 ? () => controller.moveSelected(-1) : null,
        ),
        ToolActionRow(
          key: const Key('timeline_move_later'),
          icon: CupertinoIcons.chevron_right_2,
          label: 'Move Later',
          onPressed: index >= 0 && index < count - 1
              ? () => controller.moveSelected(1)
              : null,
        ),
        const ToolSeparator(),
        ToolActionRow(
          icon: CupertinoIcons.arrow_right_to_line,
          label: 'Trim Start to Playhead',
          onPressed: clip != null && clip.isVideo
              ? () {
                  if (!controller.trimStartToPlayhead()) {
                    onError(
                      'Can’t set the start',
                      'Put the playhead inside the selected clip to set its start.',
                    );
                  }
                }
              : null,
        ),
        ToolActionRow(
          icon: CupertinoIcons.arrow_left_to_line,
          label: 'Trim End to Playhead',
          onPressed: clip == null
              ? null
              : () {
                  if (!controller.trimEndToPlayhead()) {
                    onError(
                      'Can’t set the end',
                      'Put the playhead inside the selected clip to set its end.',
                    );
                  }
                },
        ),
        const ToolSeparator(),
        ToolActionRow(
          key: const Key('timeline_replace'),
          icon: CupertinoIcons.arrow_2_squarepath,
          label: 'Replace…',
          detail: 'Keeps the grade, effects, and fades',
          onPressed: clip == null ? null : onReplace,
        ),
        ToolActionRow(
          icon: CupertinoIcons.waveform,
          label: 'Extract Audio',
          detail: 'Moves the sound to its own lane',
          onPressed: clip != null && clip.isVideo
              ? () => controller.extractAudio()
              : null,
        ),
      ],
    );
  }
}
