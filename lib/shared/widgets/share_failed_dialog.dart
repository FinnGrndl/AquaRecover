import 'package:flutter/cupertino.dart';

import 'app_dialog.dart';

/// Tells the person why the share sheet did not open.
Future<void> showShareFailedDialog(BuildContext context, Object error) {
  final message = error is StateError
      ? error.message
      : 'The share sheet could not be opened on this device. The export is still in Local Exports.';
  return showAppDialog<void>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: const Text('Could not share'),
      content: Text(message),
      actions: [
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
