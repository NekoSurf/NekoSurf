import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/chan/file_server_limit.dart';
import 'package:flutter_chan/saved/give_media.dart';
import 'package:flutter_chan/saved/permission_denied.dart';
import 'package:flutter_chan/saved/saved_folders.dart';
import 'package:flutter_chan/ui/toast.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

/// Runs [action], which saving and sharing report failures from by throwing,
/// and says what went wrong over [context]: a sheet without storage access,
/// otherwise a toast, with [message] if it isn't about access or 4chan
/// limiting downloads. Returns whether it worked.
Future<bool> reportingFailure(
  BuildContext context,
  Future<void> Function() action, {
  String message = 'Download failed :(',
}) async {
  try {
    await action();
    return true;
  } on StorageDenied {
    if (context.mounted) {
      await showCupertinoModalBottomSheet<void>(
        expand: false,
        context: context,
        builder: (context) => const PermissionDenied(),
      );
    }
  } on PhotosDenied {
    if (context.mounted) {
      showToast(context, 'Permission denied');
    }
  } catch (e) {
    debugPrint('$message: $e');
    if (context.mounted) {
      showToast(
        context,
        e is FileServerLimitedException
            ? '4chan is limiting downloads, try again soon'
            : message,
      );
    }
  }
  return false;
}
