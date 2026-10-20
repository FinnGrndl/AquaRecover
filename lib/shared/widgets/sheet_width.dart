import 'package:flutter/widgets.dart';

/// Keeps a bottom sheet at a readable width on iPad, Mac and Windows
/// windows, where a modal popup would otherwise stretch across the whole
/// window. The popup route centres the narrower sheet.
class SheetWidth extends StatelessWidget {
  const SheetWidth({super.key, this.maxWidth = 640, required this.child});

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: child,
  );
}
