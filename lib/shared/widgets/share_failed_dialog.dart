import 'package:flutter/cupertino.dart';

import '../../l10n/l10n.dart';
import '../../l10n/model_labels.dart';
import 'app_dialog.dart';

/// Tells the person why the share sheet did not open.
Future<void> showShareFailedDialog(BuildContext context, Object error) {
  final l10n = context.l10n;
  final message = error is StateError
      ? localizedKnownMessage(l10n, error.message) ?? error.message
      : l10n.shareSheetUnavailable;
  return showAppDialog<void>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: Text(l10n.couldNotShare),
      content: Text(message),
      actions: [
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.ok),
        ),
      ],
    ),
  );
}
