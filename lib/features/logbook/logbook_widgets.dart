import 'package:flutter/cupertino.dart';
import '../../shared/widgets/app_tooltip.dart';

import '../../core/logbook/dive_log.dart';
import '../../core/timeline/timeline_project.dart';
import '../timeline/timeline_theme.dart';

/// A round 44 pt glass button with a labelled symbol, as on the home screen.
class LogbookIconButton extends StatelessWidget {
  const LogbookIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => AppTooltip(
    message: label,
    child: Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(
          kMinInteractiveDimensionCupertino,
          kMinInteractiveDimensionCupertino,
        ),
        borderRadius: BorderRadius.circular(99),
        color: CupertinoColors.white.withValues(alpha: .11),
        onPressed: onPressed,
        child: Icon(icon, color: CupertinoColors.white, size: 20),
      ),
    ),
  );
}

/// A wide 44 pt action with a symbol and a title.
class LogbookActionButton extends StatelessWidget {
  const LogbookActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) => CupertinoButton(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    minimumSize: const Size(44, 44),
    borderRadius: BorderRadius.circular(12),
    color: primary ? TimelineColors.accent : TimelineColors.fill,
    onPressed: onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: CupertinoColors.white, size: 18),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              color: CupertinoColors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String formatDiveDate(DateTime t) =>
    '${_months[t.month - 1]} ${t.day}, ${t.year} · '
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// "18.4 m · 45 min · 26 °C", leaving out what is unknown.
String formatDiveStats(Dive dive) => [
  if (dive.maxDepth != null) '${dive.maxDepth!.toStringAsFixed(1)} m',
  if (dive.duration != null) '${dive.duration!.inMinutes} min',
  if (dive.waterTemperature != null)
    '${dive.waterTemperature!.toStringAsFixed(0)} °C',
].join(' · ');

/// A movie with one clip per linked medium, in capture order.
TimelineProject movieFromDive(
  List<({String path, bool isVideo, double? seconds})> media, {
  required String id,
  required String name,
}) {
  final clips = <TimelineClip>[];
  for (final item in media) {
    clips.add(
      TimelineClip(
        id: 'd${clips.length}',
        path: item.path,
        kind: item.isVideo ? TimelineClipKind.video : TimelineClipKind.image,
        sourceDuration: item.seconds,
        sourceEnd: item.isVideo ? item.seconds : null,
        transition: clips.isEmpty
            ? ClipTransition.cut
            : ClipTransition.crossfade,
      ),
    );
  }
  return TimelineProject(id: id, name: name, clips: clips);
}
