import 'package:flutter/widgets.dart';

/// Whether the person asked for less motion.
///
/// iOS reports Settings > Accessibility > Motion > Reduce Motion only as
/// [AccessibilityFeatures.reduceMotion]; it never sets
/// [MediaQuery.disableAnimationsOf], which other platforms and tests use.
/// Checking both covers every platform.
bool reduceMotionOf(BuildContext context) {
  if (MediaQuery.disableAnimationsOf(context)) return true;
  final view = View.maybeOf(context);
  return view?.platformDispatcher.accessibilityFeatures.reduceMotion ?? false;
}

/// [duration], or zero when [reduceMotionOf] is true.
Duration motionDuration(BuildContext context, Duration duration) =>
    reduceMotionOf(context) ? Duration.zero : duration;
