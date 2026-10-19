import 'package:flutter/cupertino.dart';

import '../../../../core/timeline/timeline_project.dart';
import '../../timeline_controller.dart';
import '../../timeline_theme.dart';
import 'tool_controls.dart';

/// The movie's frame shape.
class FormatPanel extends StatelessWidget {
  const FormatPanel({super.key, required this.controller});

  final TimelineController controller;

  static String use(TimelineAspect aspect) => switch (aspect) {
    TimelineAspect.landscape => 'TV, YouTube, and computers',
    TimelineAspect.portrait => 'Stories, Reels, and TikTok',
    TimelineAspect.square => 'Feeds that crop to a square',
    TimelineAspect.vertical45 => 'Portrait feed posts',
  };

  @override
  Widget build(BuildContext context) {
    final aspect = controller.project.aspect;
    final (:width, :height) = controller.project.outputSize;
    return ToolPanelBody(
      header: const ToolHeader(title: 'Format'),
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
          '${aspect.label} · $width × $height',
          style: const TextStyle(
            color: TimelineColors.text,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          use(aspect),
          style: const TextStyle(
            color: TimelineColors.secondaryText,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
