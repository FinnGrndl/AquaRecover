import 'package:flutter/cupertino.dart';

import '../../../../core/timeline/timeline_project.dart';
import '../../timeline_controller.dart';
import '../../timeline_theme.dart';
import 'tool_controls.dart';

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

  static String labelOf(ClipTransition t) => switch (t) {
    ClipTransition.cut => 'Cut',
    ClipTransition.crossfade => 'Crossfade',
    ClipTransition.dipBlack => 'Dip to black',
    ClipTransition.dipWhite => 'Dip to white',
  };

  static IconData iconOf(ClipTransition t) => switch (t) {
    ClipTransition.cut => CupertinoIcons.square_split_2x1,
    ClipTransition.crossfade => CupertinoIcons.circle_lefthalf_fill,
    ClipTransition.dipBlack => CupertinoIcons.circle_fill,
    ClipTransition.dipWhite => CupertinoIcons.circle,
  };

  @override
  Widget build(BuildContext context) {
    final clips = controller.project.clips;
    final valid = clipIndex > 0 && clipIndex < clips.length;
    final current = valid ? clips[clipIndex].transition : null;
    final seconds = controller.project.transitionSeconds;
    return ToolPanelBody(
      header: ToolHeader(
        title: 'Transition',
        subtitle: valid ? 'Clips $clipIndex–${clipIndex + 1}' : null,
      ),
      children: [
        if (!valid)
          const ToolEmptyNote('Tap the button between two clips.')
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
                      label: labelOf(t),
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
            label: 'Length of every transition',
            value: seconds,
            min: 0.1,
            max: 2,
            divisions: 19,
            enabled: current != ClipTransition.cut,
            valueLabel: secondsLabel(seconds),
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
              'Apply ${labelOf(current!)} to All',
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
