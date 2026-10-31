import 'package:flutter/cupertino.dart';

import '../../../../core/timeline/timeline_project.dart';
import '../../timeline_controller.dart';
import '../../timeline_theme.dart';
import 'tool_controls.dart';
import '../../../../l10n/timeline_labels.dart';
import '../../../../l10n/l10n.dart';

/// Opacity of the selected overlay or title.
class OpacityPanel extends StatelessWidget {
  const OpacityPanel({super.key, required this.controller});

  final TimelineController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final overlay = controller.selectedOverlay;
    return ToolPanelBody(
      header: ToolHeader(
        title: l10n.toolOpacity,
        subtitle: selectionName(context.l10n, controller),
        trailing: ToolTextButton(
          label: l10n.reset,
          onPressed: overlay == null || overlay.opacity == 1
              ? null
              : () => controller.setOpacity(1),
        ),
      ),
      children: [
        if (overlay == null)
          ToolEmptyNote(l10n.selectOverlayForOpacity)
        else
          ToolSlider(
            key: const Key('timeline_opacity_slider'),
            controller: controller,
            label: l10n.toolOpacity,
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
    final l10n = context.l10n;
    final overlay = controller.selectedOverlay;
    final options = {
      for (final a in OverlayAnimation.values) a: a.labelIn(l10n),
    };
    return ToolPanelBody(
      header: ToolHeader(
        title: l10n.animation,
        subtitle: selectionName(context.l10n, controller),
      ),
      children: [
        if (overlay == null)
          ToolEmptyNote(l10n.selectOverlayToAnimate)
        else ...[
          ToolSegmented<OverlayAnimation>(
            key: const Key('timeline_animation_in'),
            label: l10n.animationIn,
            labelWidth: 40,
            value: overlay.animationIn,
            options: options,
            onChanged: (a) => controller.setAnimation(animationIn: a),
          ),
          const SizedBox(height: 10),
          ToolSegmented<OverlayAnimation>(
            key: const Key('timeline_animation_out'),
            label: l10n.animationOut,
            labelWidth: 40,
            value: overlay.animationOut,
            options: options,
            onChanged: (a) => controller.setAnimation(animationOut: a),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.animationDuration(l10n.decimal(OverlayAnimation.seconds)),
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
    final l10n = context.l10n;
    final layer = controller.selectedLayer;
    final overlay = controller.selectedOverlay;
    final sharesLane =
        overlay != null &&
        controller.project.overlays.any(
          (o) => o.id != overlay.id && o.lane == overlay.lane,
        );
    return ToolPanelBody(
      header: ToolHeader(
        title: l10n.toolLayer,
        subtitle: layer == null ? null : l10n.layerOf(layer.layer, layer.of),
      ),
      children: [
        if (layer == null)
          ToolEmptyNote(l10n.selectOverlayOrTitle)
        else ...[
          ToolActionRow(
            key: const Key('timeline_layer_up'),
            icon: CupertinoIcons.square_stack_3d_up,
            label: l10n.bringForward,
            detail: l10n.bringForwardDetail,
            onPressed: layer.layer < layer.of || sharesLane
                ? () => controller.moveLayer(1)
                : null,
          ),
          ToolActionRow(
            key: const Key('timeline_layer_down'),
            icon: CupertinoIcons.square_stack_3d_down_right,
            label: l10n.sendBackward,
            detail: l10n.sendBackwardDetail,
            onPressed: layer.layer > 1 || sharesLane
                ? () => controller.moveLayer(-1)
                : null,
          ),
        ],
      ],
    );
  }
}
