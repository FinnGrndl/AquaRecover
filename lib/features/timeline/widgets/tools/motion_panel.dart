import 'package:flutter/cupertino.dart';

import '../../../../core/timeline/timeline_project.dart';
import '../../timeline_controller.dart';
import '../../timeline_theme.dart';
import 'tool_controls.dart';
import '../../../../l10n/l10n.dart';

/// The slow "Ken Burns" zoom of the selected photo.
class MotionPanel extends StatelessWidget {
  const MotionPanel({super.key, required this.controller});

  final TimelineController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final clip = controller.selectedClip;
    return ToolPanelBody(
      header: ToolHeader(
        title: l10n.toolMotion,
        subtitle: selectionName(context.l10n, controller),
      ),
      children: [
        if (clip == null || clip.isVideo)
          ToolEmptyNote(l10n.selectPhotoForZoom)
        else ...[
          ToolSegmented<ClipMotion>(
            value: clip.motion,
            options: {
              ClipMotion.none: l10n.motionStill,
              ClipMotion.zoomIn: l10n.motionZoomIn,
              ClipMotion.zoomOut: l10n.motionZoomOut,
            },
            onChanged: controller.setMotion,
          ),
          const SizedBox(height: 10),
          Text(
            l10n.motionDriftHint,
            style: const TextStyle(
              color: TimelineColors.secondaryText,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}
