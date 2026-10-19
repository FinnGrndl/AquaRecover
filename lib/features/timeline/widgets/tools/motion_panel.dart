import 'package:flutter/cupertino.dart';

import '../../../../core/timeline/timeline_project.dart';
import '../../timeline_controller.dart';
import '../../timeline_theme.dart';
import 'tool_controls.dart';

/// The slow "Ken Burns" zoom of the selected photo.
class MotionPanel extends StatelessWidget {
  const MotionPanel({super.key, required this.controller});

  final TimelineController controller;

  @override
  Widget build(BuildContext context) {
    final clip = controller.selectedClip;
    return ToolPanelBody(
      header: ToolHeader(title: 'Motion', subtitle: selectionName(controller)),
      children: [
        if (clip == null || clip.isVideo)
          const ToolEmptyNote('Select a photo to give it a slow zoom.')
        else ...[
          ToolSegmented<ClipMotion>(
            value: clip.motion,
            options: const {
              ClipMotion.none: 'Still',
              ClipMotion.zoomIn: 'Zoom in',
              ClipMotion.zoomOut: 'Zoom out',
            },
            onChanged: controller.setMotion,
          ),
          const SizedBox(height: 10),
          const Text(
            'For a drifting, swaying camera, try Slow Drift and Swell in '
            'Effects › Motion.',
            style: TextStyle(color: TimelineColors.secondaryText, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
