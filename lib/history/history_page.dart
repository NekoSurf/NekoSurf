import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/chan/post_text.dart';
import 'package:flutter_chan/history/history_model.dart';
import 'package:flutter_chan/history/new_replies.dart';
import 'package:flutter_chan/media/image_cache.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/ui/back_swipe_route.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_dialogs.dart';
import 'package:flutter_chan/ui/dash_header.dart';
import 'package:flutter_chan/ui/dash_menu.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';
import 'package:flutter_chan/ui/dash_widgets.dart';
import 'package:flutter_chan/ui/open.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// Every thread opened recently, newest first and grouped by day.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  @override
  void initState() {
    super.initState();
    Provider.of<HistoryProvider>(context, listen: false).checkThreads();
  }

  Future<void> _confirmClear(HistoryProvider history) async {
    final bool? confirmed = await showDashDialog<bool>(
      context: context,
      builder: (dialogContext) => DashDialog(
        title: const Text('Clear history?'),
        content: const Text('This removes every thread from your history.'),
        actions: [
          DashDialogAction(
            isDefaultAction: true,
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          DashDialogAction(
            isDestructiveAction: true,
            child: const Text('Clear'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await history.clear();
    }
  }

  static String _dayLabel(DateTime day) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final int daysAgo = today
        .difference(DateTime(day.year, day.month, day.day))
        .inDays;
    if (daysAgo == 0) {
      return 'Today';
    }
    if (daysAgo == 1) {
      return 'Yesterday';
    }
    return DateFormat(
      daysAgo < 7 ? 'EEEE' : 'EEEE, d MMM${day.year == now.year ? '' : ' y'}',
    ).format(day);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;
    final HistoryProvider history = Provider.of<HistoryProvider>(context);
    final bool tracking = Provider.of<SettingsProvider>(
      context,
    ).trackHistory.value;

    // Threads are stored newest first, so each day's group is contiguous.
    final List<(String, List<HistoryThread>)> days = [];
    for (final HistoryThread t in history.threads) {
      final String label = _dayLabel(t.visitedAt);
      if (days.isEmpty || days.last.$1 != label) {
        days.add((label, <HistoryThread>[]));
      }
      days.last.$2.add(t);
    }

    return DashScaffold(
      title: 'History',
      onRefresh: () => history.checkThreads(force: true),
      actions: [
        if (history.threads.isNotEmpty)
          DashIconButton(
            label: 'Clear history',
            icon: const Icon(CupertinoIcons.trash),
            onPressed: () => _confirmClear(history),
          ),
      ],
      slivers: [
        if (days.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  tracking
                      ? 'Threads you open show up here.'
                      : 'History is turned off in Privacy settings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: DashColors.muted(isDark)),
                ),
              ),
            ),
          ),
        for (final (String label, List<HistoryThread> threads) in days) ...[
          SliverToBoxAdapter(child: DashSectionHeader(title: label)),
          SliverList.builder(
            itemCount: threads.length,
            itemBuilder: (context, index) {
              final HistoryThread t = threads[index];
              final int? replies = history.replies(t);
              return NewRepliesCount(
                key: ValueKey(t.key),
                thread: t.no,
                replies: replies,
                builder: (_, newReplies) => _HistoryRow(
                  thread: t,
                  isArchived: history.isArchived(t),
                  newReplies: newReplies,
                  onTap: () => openThread(context, t.toPost()),
                  onRemove: () => history.removeThread(t),
                ),
              );
            },
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.thread,
    required this.isArchived,
    required this.newReplies,
    required this.onTap,
    required this.onRemove,
  });

  final HistoryThread thread;
  final bool isArchived;
  final int newReplies;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;
    final Color tint = boardColor(thread.board);
    final String title = plainText(thread.title).trim();
    final String body = plainText(thread.com ?? '').trim();
    final String headline = title.isNotEmpty
        ? title
        : (body.isNotEmpty ? body : 'No.${thread.no}');

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Slidable(
        endActionPane: swipeActions(
          label: 'Remove',
          icon: CupertinoIcons.trash_fill,
          onPressed: onRemove,
        ),
        child: SlidableBackSwipe(
          child: GestureDetector(
            onLongPress: () => showDashMenu(
              context,
              title: headline,
              entries: [
                DashMenuEntry(
                  title: 'Remove from history',
                  icon: CupertinoIcons.trash,
                  isDestructive: true,
                  onPressed: onRemove,
                ),
              ],
            ),
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
                      child: thread.imageUrl == null
                          ? Text(
                              '/${thread.board}/',
                              style: TextStyle(
                                color: tint,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            )
                          : Image(
                              image: thumbnailImage(
                                thread.toPost().thumbnailUrl,
                              ),
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox.shrink(),
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
                            Text(
                              DateFormat('kk:mm').format(thread.visitedAt),
                              style: TextStyle(
                                fontSize: 12,
                                color: DashColors.muted(isDark),
                              ),
                            ),
                            if (isArchived) ...[
                              const SizedBox(width: 6),
                              Text(
                                'Archived',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: DashColors.muted(isDark),
                                ),
                              ),
                            ],
                            const Spacer(),
                            if (newReplies > 0)
                              NewRepliesBadge(count: newReplies),
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
                            color: DashColors.text(isDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
