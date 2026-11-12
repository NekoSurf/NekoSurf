import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/saved/give_media.dart';
import 'package:flutter_chan/saved/report_failure.dart';
import 'package:flutter_chan/saved/saved_attachments_model.dart';
import 'package:flutter_chan/saved/saved_browsing.dart';
import 'package:flutter_chan/saved/saved_grid.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_dialogs.dart';
import 'package:flutter_chan/ui/dash_header.dart';
import 'package:flutter_chan/ui/dash_menu.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';
import 'package:flutter_chan/ui/toast.dart';
import 'package:provider/provider.dart';

class SavedTab extends StatefulWidget {
  const SavedTab({super.key});

  @override
  State<SavedTab> createState() => _SavedTabState();
}

class _SavedTabState extends State<SavedTab> {
  late final SavedBrowsing browsing = SavedBrowsing(
    Provider.of<SettingsProvider>(context, listen: false),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Leaving the tab ends a selection.
    if (!TickerMode.valuesOf(context).enabled && browsing.selecting) {
      browsing.setSelecting(false);
    }
  }

  @override
  void dispose() {
    browsing.dispose();
    super.dispose();
  }

  /// What's selected whose files are here: not ones still in iCloud.
  List<String> _selectedHere(SavedAttachmentsProvider saved) =>
      saved.filesHere(browsing.selected).toList();

  Future<void> _saveSelectedToPhotos(SavedAttachmentsProvider saved) async {
    final List<String> names = _selectedHere(saved);
    int failed = 0;
    final bool ran = await reportingFailure(context, () async {
      failed = await copySavedToPhotos(names);
    });
    if (ran && mounted) {
      showToast(
        context,
        failed == 0
            ? 'Saved ${names.length} to Photos'
            : '$failed of ${names.length} failed to save',
      );
    }
  }

  void _confirmDeleteSelected(SavedAttachmentsProvider saved) {
    _confirm(
      title: 'Delete ${browsing.selected.length} items?',
      message: 'They will be removed from your saved attachments.',
      action: 'Delete',
      onConfirmed: () async {
        final Set<String> names = browsing.selected.toSet();
        await reportingFailure(
          context,
          () => saved.removeFiles(names),
          message: "Couldn't delete them",
        );
        browsing.setSelecting(false);
      },
    );
  }

  void _confirm({
    required String title,
    required String message,
    required String action,
    required VoidCallback onConfirmed,
  }) {
    showDashDialog<void>(
      context: context,
      builder: (dialogContext) => DashDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          DashDialogAction(
            isDefaultAction: true,
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          DashDialogAction(
            isDestructiveAction: true,
            child: Text(action),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onConfirmed();
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _selectingActions(SavedAttachmentsProvider saved) {
    final bool hasSelection = browsing.selected.isNotEmpty;
    final bool hasFiles = saved.filesHere(browsing.selected).isNotEmpty;
    return [
      DashIconButton(
        label: 'Save to Photos',
        icon: const Icon(CupertinoIcons.arrow_down_to_line),
        onPressed: hasFiles ? () => _saveSelectedToPhotos(saved) : null,
      ),
      DashIconButton(
        label: 'Share',
        icon: const Icon(CupertinoIcons.share),
        onPressed: hasFiles
            ? () => reportingFailure(
                context,
                () => shareSaved(_selectedHere(saved)),
                message: "Couldn't share it",
              )
            : null,
      ),
      DashIconButton(
        label: 'Delete',
        icon: const Icon(CupertinoIcons.trash, color: DashColors.danger),
        onPressed: hasSelection ? () => _confirmDeleteSelected(saved) : null,
      ),
      DashMenuButton(
        menuChildren: [
          DashMenuEntry(
            title: 'Select all',
            icon: CupertinoIcons.checkmark_circle_fill,
            onPressed: () =>
                browsing.selectAll(browsing.visible(saved.attachments)),
          ),
          DashMenuEntry(
            title: 'Deselect all',
            icon: CupertinoIcons.circle,
            onPressed: browsing.deselectAll,
          ),
        ],
      ),
      DashIconButton(
        label: 'Stop selecting',
        icon: const Icon(CupertinoIcons.xmark),
        onPressed: () => browsing.setSelecting(false),
      ),
    ];
  }

  List<Widget> _browsingActions(SavedAttachmentsProvider saved) {
    return [
      DashMenuButton(
        menuChildren: [
          DashMenuEntry(
            title: 'Select',
            icon: CupertinoIcons.checkmark_circle,
            onPressed: () => browsing.setSelecting(true),
          ),
          const DashMenuDivider(),
          DashMenuEntry(
            title: 'Newest first',
            icon: CupertinoIcons.arrow_down,
            isSelected: browsing.newestFirst,
            onPressed: () => browsing.setNewestFirst(true),
          ),
          DashMenuEntry(
            title: 'Oldest first',
            icon: CupertinoIcons.arrow_up,
            isSelected: !browsing.newestFirst,
            onPressed: () => browsing.setNewestFirst(false),
          ),
          const DashMenuDivider(),
          DashMenuEntry(
            title: 'Clear attachments',
            icon: CupertinoIcons.trash,
            isDestructive: true,
            onPressed: () => _confirm(
              title: 'Clear all attachments?',
              message:
                  'This permanently deletes all saved attachments from the app.',
              action: 'Clear',
              onConfirmed: () => reportingFailure(
                context,
                saved.clear,
                message: "Couldn't delete them",
              ),
            ),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final SavedAttachmentsProvider saved =
        Provider.of<SavedAttachmentsProvider>(context);
    return ListenableBuilder(
      listenable: browsing,
      builder: (context, _) => DashScaffold(
        title: !browsing.selecting
            ? 'Saved Attachments'
            : browsing.selected.isEmpty
            ? 'Select Items'
            : '${browsing.selected.length} Selected',
        actions: browsing.selecting
            ? _selectingActions(saved)
            : _browsingActions(saved),
        reserveTabBarSpace: true,
        slivers: [SavedGrid(browsing: browsing)],
      ),
    );
  }
}
