import 'package:flutter/cupertino.dart';

import '../../timeline_controller.dart';
import 'tool_controls.dart';
import '../../../../l10n/l10n.dart';

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
    final l10n = context.l10n;
    final clip = controller.selectedClip;
    final index = controller.selectedIndex;
    final count = controller.project.clips.length;
    return ToolPanelBody(
      header: ToolHeader(
        title: l10n.toolMore,
        subtitle: selectionName(context.l10n, controller),
      ),
      children: [
        ToolActionRow(
          key: const Key('timeline_move_earlier'),
          icon: CupertinoIcons.chevron_left_2,
          label: l10n.moveEarlier,
          onPressed: index > 0 ? () => controller.moveSelected(-1) : null,
        ),
        ToolActionRow(
          key: const Key('timeline_move_later'),
          icon: CupertinoIcons.chevron_right_2,
          label: l10n.moveLater,
          onPressed: index >= 0 && index < count - 1
              ? () => controller.moveSelected(1)
              : null,
        ),
        const ToolSeparator(),
        ToolActionRow(
          icon: CupertinoIcons.arrow_right_to_line,
          label: l10n.trimStartToPlayhead,
          onPressed: clip != null && clip.isVideo
              ? () {
                  if (!controller.trimStartToPlayhead()) {
                    onError(l10n.cannotSetStart, l10n.cannotSetStartBody);
                  }
                }
              : null,
        ),
        ToolActionRow(
          icon: CupertinoIcons.arrow_left_to_line,
          label: l10n.trimEndToPlayhead,
          onPressed: clip == null
              ? null
              : () {
                  if (!controller.trimEndToPlayhead()) {
                    onError(l10n.cannotSetEnd, l10n.cannotSetEndBody);
                  }
                },
        ),
        const ToolSeparator(),
        ToolActionRow(
          key: const Key('timeline_replace'),
          icon: CupertinoIcons.arrow_2_squarepath,
          label: l10n.replaceEllipsis,
          detail: l10n.replaceDetail,
          onPressed: clip == null ? null : onReplace,
        ),
        ToolActionRow(
          icon: CupertinoIcons.waveform,
          label: l10n.extractAudio,
          detail: l10n.extractAudioDetail,
          onPressed: clip != null && clip.isVideo
              ? () => controller.extractAudio(nameOf: l10n.extractedAudioName)
              : null,
        ),
      ],
    );
  }
}
