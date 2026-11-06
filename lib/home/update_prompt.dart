import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/home/update_checker.dart';
import 'package:flutter_chan/ui/dash_dialogs.dart';
import 'package:flutter_chan/ui/open_url.dart';

Future<void> offerAppUpdate(BuildContext context) async {
  // Only phones get releases to update to.
  if (!Platform.isAndroid && !Platform.isIOS) {
    return;
  }
  final Uri? updateUrl = await checkForAppUpdate();
  if (!context.mounted || updateUrl == null) {
    return;
  }

  await showDashDialog<void>(
    context: context,
    builder: (dialogContext) => DashDialog(
      title: const Text('Update available'),
      content: Text(
        Platform.isIOS
            ? 'A newer version of NekoSurf is available on TestFlight.'
            : 'A newer version of NekoSurf is available.',
      ),
      actions: [
        DashDialogAction(
          child: const Text('Later'),
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
        DashDialogAction(
          isDefaultAction: true,
          child: Text(Platform.isIOS ? 'Open TestFlight' : 'View release'),
          onPressed: () {
            Navigator.of(dialogContext).pop();
            openUrl(updateUrl.toString());
          },
        ),
      ],
    ),
  );
}
