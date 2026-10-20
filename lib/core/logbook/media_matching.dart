import 'dive_log.dart';

/// A photo or video that might belong to a dive.
class MediaCandidate {
  const MediaCandidate({
    this.assetId,
    this.path,
    required this.isVideo,
    required this.capturedAt,
  });

  final String? assetId;
  final String? path;
  final bool isVideo;
  final DateTime capturedAt;
}

/// Depth in metres [at] a moment of [dive], interpolated between profile
/// samples. `null` when the dive has no depth profile or [at] lies outside
/// it.
double? depthAt(Dive dive, DateTime at) {
  final samples = [
    for (final s in dive.samples)
      if (s.depth != null) s,
  ];
  if (samples.isEmpty) return null;
  final t = at.difference(dive.start).inMilliseconds / 1000;
  if (t < samples.first.seconds || t > samples.last.seconds) return null;
  for (var i = 1; i < samples.length; i++) {
    final a = samples[i - 1];
    final b = samples[i];
    if (t > b.seconds) continue;
    final span = b.seconds - a.seconds;
    if (span <= 0) return b.depth;
    final f = (t - a.seconds) / span;
    return a.depth! + (b.depth! - a.depth!) * f;
  }
  return samples.last.depth;
}

/// Links each candidate to the dive it was captured during, within [margin]
/// before descent and after surfacing. Media already on a dive is not
/// added twice. Returns the updated dives (only those that changed) and how
/// many links were made.
(List<Dive>, int) matchMediaToDives(
  List<Dive> dives,
  Iterable<MediaCandidate> candidates, {
  Duration margin = const Duration(minutes: 2),
}) {
  final updated = <String, Dive>{};
  var linked = 0;
  for (final candidate in candidates) {
    for (final original in dives) {
      final dive = updated[original.id] ?? original;
      if (dive.duration == null) continue;
      final from = dive.start.subtract(margin);
      final to = dive.end.add(margin);
      final at = candidate.capturedAt;
      if (at.isBefore(from) || at.isAfter(to)) continue;
      final media = DiveMedia(
        assetId: candidate.assetId,
        path: candidate.path,
        isVideo: candidate.isVideo,
        capturedAt: at,
        depth: depthAt(dive, at),
      );
      if (dive.media.any((m) => m.key == media.key)) break;
      updated[dive.id] = dive.copyWith(media: [...dive.media, media]);
      linked++;
      break;
    }
  }
  return (updated.values.toList(), linked);
}
