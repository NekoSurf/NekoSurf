import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/ui/dash_dialogs.dart';
import 'package:provider/provider.dart';

/// Whether to go on saving [count] files to Photos: asks first, if that's
/// the setting, as Photos shows them outside the app.
Future<bool> confirmSavingToPhotos(
  BuildContext context, {
  int count = 1,
}) async {
  if (!context.read<SettingsProvider>().askBeforePhotos.value) {
    return true;
  }
  final String what = count == 1 ? 'it' : 'them';
  final bool? confirmed = await showDashDialog<bool>(
    context: context,
    builder: (dialogContext) => DashDialog(
      title: Text(count == 1 ? 'Save to Photos?' : 'Save $count to Photos?'),
      content: Text(
        'Photos shows $what in your library, and may pick $what for '
        'Memories and widgets.',
      ),
      actions: [
        DashDialogAction(
          child: const Text('Cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        DashDialogAction(
          isDefaultAction: true,
          child: const Text('Save'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
