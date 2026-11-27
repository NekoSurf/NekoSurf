import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/chan/post_text.dart';
import 'package:flutter_chan/media/image_cache.dart';
import 'package:flutter_chan/offline/offline_threads.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/settings/storage_settings.dart';
import 'package:flutter_chan/ui/back_swipe_route.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_dialogs.dart';
import 'package:flutter_chan/ui/dash_header.dart';
import 'package:flutter_chan/ui/dash_menu.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';
import 'package:flutter_chan/ui/dash_widgets.dart';
import 'package:flutter_chan/ui/empty_state.dart';
import 'package:flutter_chan/ui/open.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// Opens the threads saved for offline.
void openOfflineThreads(BuildContext context) => Navigator.of(
  context,
).push(BackSwipePageRoute<void>(builder: (_) => const OfflineThreadsPage()));

/// The threads saved for offline, newest first, to open or remove.
class OfflineThreadsPage extends StatelessWidget {
  const OfflineThreadsPage({super.key});

  Future<void> _confirmRemoveAll(
    BuildContext context,
    OfflineThreads offline,
    SettingsProvider settings,
  ) async {
    final bool? confirmed = await showDashDialog<bool>(
      context: context,
      builder: (dialogContext) => DashDialog(
        title: const Text('Remove all?'),
        content: const Text(
          'This deletes every thread listed here, with its images and '
          'videos.',
        ),
        actions: [
          DashDialogAction(
            isDefaultAction: true,
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          DashDialogAction(
            isDestructiveAction: true,
            child: const Text('Remove'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      // Not those of boards that are hidden: they aren't on show.
      await offline.removeAll(where: (t) => !settings.hidesBoard(t.board));
    }
  }

  @override
  Widget build(BuildContext context) {
    final OfflineThreads offline = Provider.of<OfflineThreads>(context);
    final SettingsProvider settings = Provider.of<SettingsProvider>(context);
    final List<OfflineThread> threads = <OfflineThread>[
      for (final OfflineThread t in offline.threads)
        if (!settings.hidesBoard(t.board)) t,
    ];

    return DashScaffold(
      title: 'Saved for offline',
      subtitle: threads.isEmpty
          ? null
          : '${threads.length == 1 ? '1 thread' : '${threads.length} threads'}'
                ' · ${formatStorageSize(OfflineThreads.bytesOf(threads))}',
      readable: true,
      actions: [
        if (threads.isNotEmpty)
          DashIconButton(
            label: 'Remove all',
            icon: const Icon(CupertinoIcons.trash),
            onPressed: () => _confirmRemoveAll(context, offline, settings),
          ),
      ],
      slivers: [
        if (threads.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: DashEmptyState(
              icon: CupertinoIcons.arrow_down_circle,
              title: 'Nothing saved for offline',
              message:
                  'Save a thread for offline from its menu, and it stays '
                  'here with its images and videos, to read without a '
                  'connection.',
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          sliver: SliverList.builder(
            itemCount: threads.length,
            itemBuilder: (context, index) {
              final OfflineThread t = threads[index];
              return _OfflineRow(
                key: ValueKey(t.key),
                thread: t,
                saving: offline.savingProgress(t.board, t.no),
                onTap: () => openThread(context, t.toPost()),
                onRemove: () => offline.remove(t.board, t.no),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OfflineRow extends StatelessWidget {
  const _OfflineRow({
    super.key,
    required this.thread,
    required this.saving,
    required this.onTap,
    required this.onRemove,
  });

  final OfflineThread thread;
  final double? saving;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  void _showMenu(BuildContext context, String headline) {
    showDashMenu(
      context,
      title: headline,
      entries: [
        DashMenuEntry(
          title: 'Remove',
          icon: CupertinoIcons.trash,
          isDestructive: true,
          onPressed: onRemove,
        ),
      ],
    );
  }

  String get _details {
    final double? saving = this.saving;
    if (saving != null) {
      return 'Saving · ${(saving * 100).round()}%';
    }
    final int media = thread.mediaCount;
    return <String>[
      if (media == 1) '1 file' else '$media files',
      formatStorageSize(thread.bytes),
      DateFormat('d MMM').format(thread.savedAt),
      if (thread.missing > 0) '${thread.missing} missing',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final Color tint = boardColor(thread.board);
    final String title = plainText(thread.title).trim();
    final String body = plainText(thread.com ?? '').trim();
    final String headline = title.isNotEmpty
        ? title
        : (body.isNotEmpty ? body : 'No.${thread.no}');
    final bool removable = saving == null;

    final Widget card = GestureDetector(
      onLongPress: removable ? () => _showMenu(context, headline) : null,
      // A right click, with a trackpad or mouse, does what holding does.
      onSecondaryTap: removable ? () => _showMenu(context, headline) : null,
      child: DashCard(
        radius: 18,
        onTap: onTap,
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 64,
                height: 64,
                color: tint.withValues(alpha: 0.16),
                alignment: Alignment.center,
                child: thread.thumbnailName == null
                    ? Text(
                        '/${thread.board}/',
                        style: TextStyle(
                          color: tint,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : Image(
                        image: thumbnailImage(thread.toPost().thumbnailUrl),
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '/${thread.board}/',
                        style: TextStyle(
                          color: tint,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _details,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: DashColors.muted(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      color: DashColors.text(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: removable
          ? Slidable(
              endActionPane: swipeActions(
                label: 'Remove',
                icon: CupertinoIcons.trash_fill,
                onPressed: onRemove,
              ),
              child: SlidableBackSwipe(child: card),
            )
          : card,
    );
  }
}
