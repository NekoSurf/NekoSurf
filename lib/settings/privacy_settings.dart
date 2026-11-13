import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/history/history_model.dart';
import 'package:flutter_chan/saved/saved_attachments_model.dart';
import 'package:flutter_chan/saved/saved_folders.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/settings/settings_widgets.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/toast.dart';
import 'package:provider/provider.dart';

/// What shows of NSFW boards, and what of the app others can see: on the
/// phone, in Files and Photos, and in the app switcher; and history.
class PrivacySettings extends StatelessWidget {
  const PrivacySettings({super.key});

  /// Moves saved files into the app's own folder, or back where other apps
  /// can see them.
  static Future<void> _setSavedFilesHidden(
    BuildContext context,
    bool hidden,
  ) async {
    final SavedAttachmentsProvider saved = context
        .read<SavedAttachmentsProvider>();
    final SettingsProvider settings = context.read<SettingsProvider>();
    // A save going on would put its file where they were.
    if (!saved.saves.isIdle) {
      showToast(context, 'Wait until saving is done');
      return;
    }
    // Android's Download folder needs storage access, either way.
    if (!await canMoveSavedFiles()) {
      if (context.mounted) {
        showToast(context, 'Storage access is needed to move them');
      }
      return;
    }
    try {
      await saved.moveFiles(hidden: hidden);
      await settings.savedFilesHidden.set(hidden);
    } catch (e) {
      debugPrint('Moving saved files failed: $e');
      if (context.mounted) {
        showToast(context, "Couldn't move your saved files");
      }
    }
  }

  /// [row], greyed out and not to be changed unless [enabled]: it stays in
  /// its place, so the rows below don't move when it's turned on or off.
  static Widget _enabledIf(bool enabled, Widget row) => IgnorePointer(
    ignoring: !enabled,
    child: AnimatedOpacity(
      opacity: enabled ? 1 : 0.4,
      duration: const Duration(milliseconds: 200),
      child: row,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final HistoryProvider history = Provider.of<HistoryProvider>(
      context,
      listen: false,
    );
    final bool nsfw = settings.allowNSFW.value;

    return Column(
      children: [
        SettingsGroup(
          title: 'Privacy',
          children: [
            SettingsRow(
              icon: CupertinoIcons.exclamationmark_triangle_fill,
              color: DashColors.danger,
              title: 'Allow NSFW boards',
              subtitle:
                  'Show them and their threads in the board list, your '
                  'feed, search, bookmarks and history',
              trailing: SettingsSwitch(
                value: nsfw,
                onChanged: settings.allowNSFW.set,
              ),
            ),
            _enabledIf(
              nsfw,
              SettingsRow(
                icon: CupertinoIcons.flame_fill,
                color: const Color(0xFFFB923C),
                title: 'Turn on each time',
                subtitle:
                    'Hidden until you tap the flame on Boards, and again '
                    'once the app is closed',
                trailing: SettingsSwitch(
                  value: settings.nsfwEachSession.value,
                  onChanged: settings.nsfwEachSession.set,
                ),
              ),
            ),
            _enabledIf(
              nsfw,
              SettingsRow(
                icon: CupertinoIcons.eye_slash_fill,
                color: const Color(0xFFA78BFA),
                title: 'Cover NSFW images',
                subtitle:
                    'Images on NSFW boards stay covered until you tap them',
                trailing: SettingsSwitch(
                  value: settings.blurNsfwImages.value,
                  onChanged: settings.blurNsfwImages.set,
                ),
              ),
            ),
            SettingsRow(
              icon: CupertinoIcons.paperclip,
              color: const Color(0xFF60A5FA),
              title: 'Show the Saved tab',
              subtitle: 'Without it, open Saved from History',
              trailing: SettingsSwitch(
                value: settings.showSavedTab.value,
                onChanged: settings.showSavedTab.set,
              ),
            ),
            ValueListenableBuilder<(int, int)?>(
              valueListenable: context.read<SavedAttachmentsProvider>().moving,
              builder: (context, moving, _) => SettingsRow(
                icon: CupertinoIcons.folder_fill,
                color: const Color(0xFF34D399),
                title: 'Keep saved files in the app',
                subtitle: switch (moving) {
                  // Copying out of Download, on Android, can take a while.
                  (final int done, final int total) when total > 0 =>
                    'Moving $done of $total…',
                  (_, _) => 'Moving…',
                  null when Platform.isAndroid =>
                    "Other apps can't see them in your Download folder",
                  null => "Other apps, like Files, can't see them",
                },
                trailing: moving != null
                    ? const CupertinoActivityIndicator()
                    : SettingsSwitch(
                        value: settings.savedFilesHidden.value,
                        onChanged: (hidden) =>
                            _setSavedFilesHidden(context, hidden),
                      ),
              ),
            ),
            SettingsRow(
              icon: CupertinoIcons.photo_fill,
              color: const Color(0xFFF472B6),
              title: 'Ask before saving to Photos',
              subtitle:
                  'Photos shows what you save in your library, and may '
                  'pick it for Memories and widgets',
              trailing: SettingsSwitch(
                value: settings.askBeforePhotos.value,
                onChanged: settings.askBeforePhotos.set,
              ),
            ),
            SettingsRow(
              icon: CupertinoIcons.rectangle_on_rectangle_angled,
              color: const Color(0xFFFBBF24),
              title: 'Hide in the app switcher',
              subtitle: Platform.isAndroid
                  ? "Show a blank screen there instead of what's open. On "
                        'Android 12 and older, this also blocks screenshots.'
                  : "Blur what's open there, so it can't be read",
              trailing: SettingsSwitch(
                value: settings.coverInAppSwitcher.value,
                onChanged: settings.coverInAppSwitcher.set,
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: 'History',
          children: [
            SettingsRow(
              icon: CupertinoIcons.clock_fill,
              color: const Color(0xFF60A5FA),
              title: 'Track history',
              subtitle:
                  'List the threads you open on the History page. Turning this '
                  'off also clears what is stored.',
              trailing: SettingsSwitch(
                value: settings.trackHistory.value,
                onChanged: history.setTracking,
              ),
            ),
            _enabledIf(
              settings.trackHistory.value,
              SettingsRow(
                icon: CupertinoIcons.timer,
                color: const Color(0xFFFBBF24),
                title: 'Only while the app is open',
                subtitle:
                    'Forget them when you leave the app. They are never '
                    'stored or synced.',
                trailing: SettingsSwitch(
                  value: settings.historyThisSessionOnly.value,
                  onChanged: history.setSessionOnly,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
