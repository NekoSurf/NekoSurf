import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/board/thread_order.dart';
import 'package:flutter_chan/chan/catalog.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/settings/settings_widgets.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_dialogs.dart';
import 'package:flutter_chan/ui/dash_menu.dart';
import 'package:provider/provider.dart';

/// What boards, threads and their media look like and do.
class BrowsingSettings extends StatelessWidget {
  const BrowsingSettings({super.key});

  static void _showAddFilter(BuildContext context, SettingsProvider settings) {
    final TextEditingController controller = TextEditingController();
    showDashDialog<void>(
      context: context,
      builder: (ctx) => DashDialog(
        title: const Text('Hide threads matching'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A plain word hides as a keyword; regex works too. '
              'Matching is case-insensitive against the thread title '
              'and comment.',
            ),
            const SizedBox(height: 12),
            DashDialogField(
              controller: controller,
              placeholder: r'e.g. crypto|ai slop|general',
              isCode: true,
            ),
          ],
        ),
        actions: [
          DashDialogAction(
            isDefaultAction: true,
            onPressed: () {
              settings.addHiddenThreadPattern(controller.text);
              controller.clear();
            },
            child: const Text('Add & add another'),
          ),
          DashDialogAction(
            onPressed: () {
              settings.addHiddenThreadPattern(controller.text);
              Navigator.of(ctx).pop();
            },
            child: const Text('Add'),
          ),
          DashDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    return Column(
      children: [
        SettingsGroup(
          title: 'Boards',
          footer:
              'Boards open in this order. To change it for one board, use the '
              'menu on that board.',
          children: [
            DashMenuAnchor(
              menuChildren: [
                for (final sort in Sort.values)
                  DashMenuEntry(
                    title: sort.title,
                    icon: sort.icon,
                    isSelected: settings.boardSort.value == sort,
                    onPressed: () => settings.boardSort.set(sort),
                  ),
              ],
              builder: (context, open) => SettingsRow(
                icon: CupertinoIcons.sort_down,
                color: const Color(0xFFFB923C),
                title: 'Sort by',
                value: settings.boardSort.value.title,
                onTap: open,
              ),
            ),
            SettingsRow(
              icon: CupertinoIcons.arrow_up_arrow_down,
              color: const Color(0xFF34D399),
              title: 'Direction',
              trailing: SettingsSegments<SortDirection>(
                value: settings.boardSortDirection.value,
                onChanged: settings.boardSortDirection.set,
                segments: const {
                  SortDirection.desc: 'Desc',
                  SortDirection.asc: 'Asc',
                },
              ),
            ),
            SettingsRow(
              icon: CupertinoIcons.square_grid_2x2_fill,
              color: context.accent,
              title: 'View',
              trailing: SettingsSegments<ViewMode>(
                value: settings.boardViewMode.value,
                onChanged: settings.boardViewMode.set,
                segments: const {ViewMode.grid: 'Grid', ViewMode.list: 'List'},
              ),
            ),
            SettingsRow(
              icon: CupertinoIcons.exclamationmark_triangle_fill,
              color: DashColors.danger,
              title: 'Allow NSFW boards',
              subtitle: 'Show them in the board list and your feed',
              trailing: SettingsSwitch(
                value: settings.allowNSFW.value,
                onChanged: settings.allowNSFW.set,
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Threads',
          footer:
              'Nested puts each reply under the post it answers, so you can '
              'fold whole conversations. Flat lists every post in the order '
              'it was posted.',
          children: [
            SettingsRow(
              icon: CupertinoIcons.arrow_down_circle_fill,
              color: const Color(0xFF60A5FA),
              title: 'Auto-scroll to last seen',
              subtitle: 'Open threads where you left them',
              trailing: SettingsSwitch(
                value: settings.autoScrollToLastSeen.value,
                onChanged: settings.autoScrollToLastSeen.set,
              ),
            ),
            SettingsRow(
              icon: CupertinoIcons.list_bullet_indent,
              color: const Color(0xFFA78BFA),
              title: 'Layout',
              trailing: SettingsSegments<ThreadLayout>(
                value: settings.threadLayout.value,
                onChanged: settings.threadLayout.set,
                segments: const {
                  ThreadLayout.nested: 'Nested',
                  ThreadLayout.flat: 'Flat',
                },
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Media',
          children: [
            SettingsRow(
              icon: CupertinoIcons.speaker_slash_fill,
              color: const Color(0xFFF472B6),
              title: 'Start feed videos muted',
              subtitle: 'Videos in the thread feed autoplay without sound',
              trailing: SettingsSwitch(
                value: settings.feedVideosStartMuted.value,
                onChanged: settings.feedVideosStartMuted.set,
              ),
            ),
            SettingsRow(
              icon: CupertinoIcons.antenna_radiowaves_left_right,
              color: const Color(0xFF34D399),
              title: 'Data saver',
              subtitle:
                  'Threads show only thumbnails. Images and videos load when '
                  'you open them.',
              trailing: SettingsSwitch(
                value: settings.dataSaver.value,
                onChanged: settings.dataSaver.set,
              ),
            ),
            SettingsRow(
              icon: CupertinoIcons.number_square_fill,
              color: const Color(0xFFFBBF24),
              title: "Use 4chan's file names",
              subtitle:
                  'Name files you save or share by their number on 4chan, like '
                  '1700000000000.jpg. Files already saved keep their names.',
              trailing: SettingsSwitch(
                value: settings.serverFileNames.value,
                onChanged: settings.serverFileNames.set,
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Hidden threads',
          footer:
              'Matching is case-insensitive against the thread title and '
              'comment, in boards and the feed. Invalid regex is treated as a '
              'plain keyword.',
          children: [
            for (final String pattern in settings.hiddenThreadPatterns)
              SettingsRow(
                icon: CupertinoIcons.eye_slash_fill,
                color: DashColors.danger,
                title: pattern,
                trailing: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => settings.removeHiddenThreadPattern(pattern),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      CupertinoIcons.xmark_circle_fill,
                      size: 20,
                      color: CupertinoColors.systemGrey,
                    ),
                  ),
                ),
              ),
            SettingsRow(
              icon: CupertinoIcons.add_circled_solid,
              color: context.accent,
              title: 'Add filter',
              subtitle: 'Keyword or regex',
              onTap: () => _showAddFilter(context, settings),
            ),
          ],
        ),
      ],
    );
  }
}
