/// Timing rules shared by main clips, overlays, and audio items.
library;

/// Playback speed limits for videos on the main track and on overlay lanes.
abstract final class TimelineSpeed {
  static const min = 0.25;
  static const max = 4.0;

  /// [speed] clamped to [min]…[max]; non-finite values play at 1×.
  static double clamp(double speed) =>
      speed.isFinite ? speed.clamp(min, max).toDouble() : 1;
}

/// Fade lengths each clamped to `0…maxSeconds` and, when together longer than
/// [duration], scaled down proportionally so they meet without overlapping.
({double fadeIn, double fadeOut}) resolveFades(
  double fadeIn,
  double fadeOut,
  double duration, {
  double maxSeconds = 3,
}) {
  double clean(double v) =>
      v.isFinite ? v.clamp(0.0, maxSeconds).toDouble() : 0.0;
  var fi = clean(fadeIn), fo = clean(fadeOut);
  final total = fi + fo;
  if (duration <= 0) return (fadeIn: 0, fadeOut: 0);
  if (total > duration) {
    final k = duration / total;
    fi *= k;
    fo *= k;
  }
  return (fadeIn: fi, fadeOut: fo);
}
