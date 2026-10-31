import 'package:flutter/cupertino.dart';

import '../../../../core/timeline/timeline_project.dart';
import '../../timeline_controller.dart';
import '../../timeline_theme.dart';
import 'tool_controls.dart';
import '../../../../l10n/l10n.dart';

/// How clip [clipIndex] enters from the clip before it: a cut, a crossfade,
/// or a dip through black or white, plus the project's transition length
/// and "Apply to all".
class TransitionPanel extends StatelessWidget {
  const TransitionPanel({
    super.key,
    required this.controller,
    required this.clipIndex,
  });

  final TimelineController controller;
  final int clipIndex;

  static String labelOf(AppLocalizations l10n, ClipTransition t) => switch (t) {
    ClipTransition.cut => l10n.transitionCut,
    ClipTransition.crossfade => l10n.transitionCrossfade,
    ClipTransition.dipBlack => l10n.transitionDipBlack,
    ClipTransition.dipWhite => l10n.transitionDipWhite,
  };

  static IconData iconOf(ClipTransition t) => switch (t) {
    ClipTransition.cut => CupertinoIcons.square_split_2x1,
    ClipTransition.crossfade => CupertinoIcons.circle_lefthalf_fill,
    ClipTransition.dipBlack => CupertinoIcons.circle_fill,
    ClipTransition.dipWhite => CupertinoIcons.circle,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final clips = controller.project.clips;
    final valid = clipIndex > 0 && clipIndex < clips.length;
    final current = valid ? clips[clipIndex].transition : null;
    final seconds = controller.project.transitionSeconds;
    return ToolPanelBody(
      header: ToolHeader(
        title: l10n.toolTransition,
        subtitle: valid ? l10n.clipsRange(clipIndex, clipIndex + 1) : null,
      ),
      children: [
        if (!valid)
          ToolEmptyNote(l10n.tapBetweenClips)
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth / 4).clamp(64.0, 92.0);
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final t in ClipTransition.values)
                    ChoiceTile(
                      key: Key('timeline_transition_${t.name}'),
                      width: width,
                      label: labelOf(l10n, t),
                      icon: iconOf(t),
                      selected: t == current,
                      onPressed: () => controller.setTransitionAt(clipIndex, t),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          ToolSlider(
            key: const Key('timeline_transition_seconds'),
            controller: controller,
            label: l10n.transitionLength,
            value: seconds,
            min: 0.1,
            max: 2,
            divisions: 19,
            enabled: current != ClipTransition.cut,
            valueLabel: secondsLabel(l10n, seconds),
            onChanged: controller.setTransitionSeconds,
          ),
          const SizedBox(height: 4),
          CupertinoButton(
            key: const Key('timeline_transition_all'),
            padding: const EdgeInsets.symmetric(vertical: 11),
            color: TimelineColors.fill,
            borderRadius: BorderRadius.circular(99),
            onPressed: clips.length > 2
                ? () => controller.applyTransitionToAll(current!)
                : null,
            child: Text(
              l10n.applyTransitionToAll(labelOf(l10n, current!)),
              style: const TextStyle(
                color: TimelineColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
