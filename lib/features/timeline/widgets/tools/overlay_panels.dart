import 'package:flutter/cupertino.dart';

import '../../../../core/timeline/timeline_project.dart';
import '../../timeline_controller.dart';
import '../../timeline_theme.dart';
import 'tool_controls.dart';

/// Opacity of the selected overlay or title.
class OpacityPanel extends StatelessWidget {
  const OpacityPanel({super.key, required this.controller});

  final TimelineController controller;

  @override
  Widget build(BuildContext context) {
    final overlay = controller.selectedOverlay;
    return ToolPanelBody(
      header: ToolHeader(
        title: 'Opacity',
        subtitle: selectionName(controller),
        trailing: ToolTextButton(
          label: 'Reset',
          onPressed: overlay == null || overlay.opacity == 1
              ? null
              : () => controller.setOpacity(1),
        ),
      ),
      children: [
        if (overlay == null)
          const ToolEmptyNote('Select an overlay to change its opacity.')
        else
          ToolSlider(
            key: const Key('timeline_opacity_slider'),
            controller: controller,
            label: 'Opacity',
            value: overlay.opacity,
            min: 0,
            max: 1,
            valueLabel: percentLabel(overlay.opacity),
            onChanged: controller.setOpacity,
          ),
      ],
    );
  }
}

/// How the selected overlay or title enters and leaves.
class AnimationPanel extends StatelessWidget {
  const AnimationPanel({super.key, required this.controller});

  final TimelineController controller;

  @override
  Widget build(BuildContext context) {
    final overlay = controller.selectedOverlay;
    final options = {for (final a in OverlayAnimation.values) a: a.label};
    return ToolPanelBody(
      header: ToolHeader(
        title: 'Animation',
        subtitle: selectionName(controller),
      ),
      children: [
        if (overlay == null)
          const ToolEmptyNote('Select an overlay or title to animate it.')
        else ...[
          ToolSegmented<OverlayAnimation>(
            key: const Key('timeline_animation_in'),
            label: 'In',
            labelWidth: 40,
            value: overlay.animationIn,
            options: options,
            onChanged: (a) => controller.setAnimation(animationIn: a),
          ),
          const SizedBox(height: 10),
          ToolSegmented<OverlayAnimation>(
            key: const Key('timeline_animation_out'),
            label: 'Out',
            labelWidth: 40,
            value: overlay.animationOut,
            options: options,
            onChanged: (a) => controller.setAnimation(animationOut: a),
          ),
          const SizedBox(height: 10),
          Text(
            'Each animation takes '
            '${OverlayAnimation.seconds.toStringAsFixed(1)} s.',
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

/// Moves the selected overlay or title in front of or behind others.
class LayerPanel extends StatelessWidget {
  const LayerPanel({super.key, required this.controller});

  final TimelineController controller;

  @override
  Widget build(BuildContext context) {
    final layer = controller.selectedLayer;
    final overlay = controller.selectedOverlay;
    final sharesLane =
        overlay != null &&
        controller.project.overlays.any(
          (o) => o.id != overlay.id && o.lane == overlay.lane,
        );
    return ToolPanelBody(
      header: ToolHeader(
        title: 'Layer',
        subtitle: layer == null ? null : '${layer.layer} of ${layer.of}',
      ),
      children: [
        if (layer == null)
          const ToolEmptyNote('Select an overlay or title.')
        else ...[
          ToolActionRow(
            key: const Key('timeline_layer_up'),
            icon: CupertinoIcons.square_stack_3d_up,
            label: 'Bring Forward',
            detail: 'Shows in front of the layer above',
            onPressed: layer.layer < layer.of || sharesLane
                ? () => controller.moveLayer(1)
                : null,
          ),
          ToolActionRow(
            key: const Key('timeline_layer_down'),
            icon: CupertinoIcons.square_stack_3d_down_right,
            label: 'Send Backward',
            detail: 'Shows behind the layer below',
            onPressed: layer.layer > 1 || sharesLane
                ? () => controller.moveLayer(-1)
                : null,
          ),
        ],
      ],
    );
  }
}
