import 'package:flutter/cupertino.dart';
import '../../shared/widgets/app_tooltip.dart';

import '../../core/logbook/dive_log.dart';
import '../../core/timeline/timeline_project.dart';
import '../../l10n/l10n.dart';
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

/// "Oct 11, 2026 · 09:41" in the app language.
String formatDiveDate(AppLocalizations l10n, DateTime t) =>
    '${l10n.mediumDate(t)} · ${l10n.time24(t)}';

/// "18.4 m · 45 min · 26 °C", leaving out what is unknown.
String formatDiveStats(AppLocalizations l10n, Dive dive) => [
  if (dive.maxDepth != null) l10n.depthValue(dive.maxDepth!),
  if (dive.duration != null) l10n.minutesValue(dive.duration!.inMinutes),
  if (dive.waterTemperature != null)
    l10n.temperatureValue(dive.waterTemperature!),
].join(' · ');

/// "#12 Blue Hole", or "Dive 12" without a site, in the app language. The
/// files the logbook exports use the English [diveTitle].
String diveTitleIn(AppLocalizations l10n, Dive dive, DiveSite? site) {
  final name = site?.name.trim() ?? '';
  if (dive.number <= 0) return name.isEmpty ? l10n.diveTitleUnnamed : name;
  return name.isEmpty
      ? l10n.diveTitleNumber(dive.number)
      : l10n.diveTitleNumberSite(dive.number, name);
}

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
