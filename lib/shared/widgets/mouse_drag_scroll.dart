import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Lets a mouse drag the horizontal scrollables in [child] like a finger.
///
/// Flutter scrolls by dragging only for touch, stylus and trackpad input,
/// and a plain mouse wheel moves vertical lists only. Without this, strips
/// such as presets, the timeline or the precision wheel cannot be moved with
/// a mouse on Windows, or with a mouse on a Mac. Wrap only horizontal
/// scrollables, so mouse text selection in vertical forms keeps working.
class MouseDragScroll extends StatelessWidget {
  const MouseDragScroll({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final behavior = ScrollConfiguration.of(context);
    return ScrollConfiguration(
      behavior: behavior.copyWith(
        dragDevices: {...behavior.dragDevices, PointerDeviceKind.mouse},
      ),
      child: child,
    );
  }
}
