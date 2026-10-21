import 'dart:async';

import 'package:flutter/cupertino.dart';

/// [showCupertinoDialog] whose alert closes with Escape on a keyboard, as
/// Cancel does on macOS and Windows. Taps outside still do nothing unless
/// [barrierDismissible] is set, as with iOS alerts. Closing this way returns
/// null, the same as Cancel.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
}) {
  return showCupertinoDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) => EscapeToDismiss(child: builder(dialogContext)),
  );
}

/// Lets Escape pop the route [child] sits in, even when the route itself
/// ignores taps outside it.
class EscapeToDismiss extends StatefulWidget {
  const EscapeToDismiss({super.key, required this.child});

  final Widget child;

  @override
  State<EscapeToDismiss> createState() => _EscapeToDismissState();
}

class _EscapeToDismissState extends State<EscapeToDismiss> {
  final _focus = FocusNode(debugLabel: 'EscapeToDismiss');

  @override
  void initState() {
    super.initState();
    // Focus inside the dialog, so the key finds the action above, unless
    // a field in it took focus already.
    // After the frame and after the focus manager's own pass, which runs
    // as a microtask and applies a field's autofocus.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => scheduleMicrotask(() {
        if (!mounted) return;
        final primary = FocusManager.instance.primaryFocus;
        final inside =
            primary != null &&
            (primary == _focus || primary.ancestors.contains(_focus));
        if (!inside) _focus.requestFocus();
      }),
    );
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: {
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) {
            Navigator.of(context).maybePop();
            return null;
          },
        ),
      },
      child: Focus(focusNode: _focus, child: widget.child),
    );
  }
}
