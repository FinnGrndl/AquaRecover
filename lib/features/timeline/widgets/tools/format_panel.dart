import 'package:flutter/cupertino.dart';

import '../../../../core/timeline/timeline_project.dart';
import '../../timeline_controller.dart';
import '../../timeline_theme.dart';
import 'tool_controls.dart';
import '../../../../l10n/timeline_labels.dart';
import '../../../../l10n/l10n.dart';

/// The movie's frame shape.
class FormatPanel extends StatelessWidget {
  const FormatPanel({super.key, required this.controller});

  final TimelineController controller;

  static String use(AppLocalizations l10n, TimelineAspect aspect) =>
      switch (aspect) {
        TimelineAspect.landscape => l10n.formatUseLandscape,
        TimelineAspect.portrait => l10n.formatUsePortrait,
        TimelineAspect.square => l10n.formatUseSquare,
        TimelineAspect.vertical45 => l10n.formatUsePortrait45,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final aspect = controller.project.aspect;
    final (:width, :height) = controller.project.outputSize;
    return ToolPanelBody(
      header: ToolHeader(title: l10n.toolFormat),
      children: [
        ToolSegmented<TimelineAspect>(
          key: const Key('timeline_format_aspect'),
          value: aspect,
          options: {
            for (final a in TimelineAspect.values)
              a: '${a.widthRatio}:${a.heightRatio}',
          },
          onChanged: controller.setAspect,
        ),
        const SizedBox(height: 10),
        Text(
          l10n.formatSummary(aspect.labelIn(l10n), width, height),
          style: const TextStyle(
            color: TimelineColors.text,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          use(l10n, aspect),
          style: const TextStyle(
            color: TimelineColors.secondaryText,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
