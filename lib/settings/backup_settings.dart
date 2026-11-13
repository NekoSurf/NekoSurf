import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/saved/downloads.dart';
import 'package:flutter_chan/saved/give_media.dart';
import 'package:flutter_chan/saved/saved_folders.dart';
import 'package:flutter_chan/settings/backup.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/settings/settings_widgets.dart';
import 'package:flutter_chan/sync/cloud_sync.dart';
import 'package:flutter_chan/sync/sync_items.dart';
import 'package:flutter_chan/ui/app_restart.dart';
import 'package:flutter_chan/ui/dash_dialogs.dart';
import 'package:flutter_chan/ui/toast.dart';
import 'package:path_provider/path_provider.dart';

/// How a backup file to restore is picked; replaced in tests.
@visibleForTesting
Future<String?> Function() pickBackupFile = () async {
  final PlatformFile? file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['zip'],
  );
  return file?.path;
};

/// Backing up the saved media, bookmarks, history and settings to a file,
/// and restoring them.
class BackupSettings extends StatefulWidget {
  const BackupSettings({super.key});

  @override
  State<BackupSettings> createState() => _BackupSettingsState();
}

class _BackupSettingsState extends State<BackupSettings> {
  bool _makingFile = false;

  Future<void> _backUpToFile() async {
    final AppRestart app = AppRestart.of(context);
    setState(() => _makingFile = true);
    Directory? into;
    try {
      into = Directory('${(await getTemporaryDirectory()).path}/backup');
      await deleteQuietly(into);
      await into.create(recursive: true);
      final File zip = await createBackupFile(
        app.prefs,
        await openSavedFolders(),
        into,
      );
      await shareFile(zip, mimeType: 'application/zip');
    } on StorageDenied {
      if (mounted) {
        showToast(context, 'NekoSurf needs storage access to back up');
      }
    } catch (e) {
      debugPrint('Backing up failed: $e');
      if (mounted) {
        showToast(context, "Couldn't make the backup");
      }
    } finally {
      // Shared by now: Save to Files has its own copy.
      if (into != null) {
        await deleteQuietly(into);
      }
      if (mounted) {
        setState(() => _makingFile = false);
      }
    }
  }

  Future<void> _restoreFromFile() async {
    final AppRestart app = AppRestart.of(context);
    final String? path = await pickBackupFile();
    if (path == null || !mounted) {
      return;
    }
    final CloudSync sync = CloudSync.instance;
    final bool? confirmed = await showDashDialog<bool>(
      context: context,
      builder: (dialogContext) => DashDialog(
        title: const Text('Restore this backup?'),
        content: Text(
          'Your bookmarks, history and settings are replaced by the '
          "backup's, and its saved media is added to yours."
          '${sync.isOn ? ' iCloud sync brings the same to your other devices.' : ''}',
        ),
        actions: [
          DashDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          DashDialogAction(
            isDefaultAction: true,
            child: const Text('Restore'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) {
      return;
    }
    await app.restart(() async {
      final List<SyncItem> before = sync.isOn
          ? await sync.snapshot()
          : const [];
      await restoreBackupFile(
        path,
        app.prefs,
        await openSavedFolders(),
        await getTemporaryDirectory(),
      );
      await SettingsProvider.noteAllChanged(app.prefs);
      await sync.pushChangesSince(before);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      title: 'Backup',
      children: [
        SettingsRow(
          icon: CupertinoIcons.square_arrow_up_fill,
          color: const Color(0xFF34D399),
          title: 'Back up to a file',
          subtitle:
              'Your saved media, bookmarks, history and settings in one file, '
              'to keep in Files or anywhere.',
          trailing: _makingFile ? const CupertinoActivityIndicator() : null,
          onTap: _makingFile ? null : _backUpToFile,
        ),
        SettingsRow(
          icon: CupertinoIcons.arrow_counterclockwise_circle_fill,
          color: const Color(0xFFFBBF24),
          title: 'Restore from a file',
          subtitle: 'A backup made with Back up to a file.',
          onTap: _restoreFromFile,
        ),
      ],
    );
  }
}
