import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/board/thread_order.dart';
import 'package:flutter_chan/chan/catalog.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/settings/settings_widgets.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_dialogs.dart';
import 'package:flutter_chan/ui/dash_menu.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';
import 'package:provider/provider.dart';

class ThreadsSettings extends StatelessWidget {
  const ThreadsSettings({super.key});

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
              placeholder: r'e.g. crypto|ai slop|general',
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

    return DashScaffold(
      title: 'Threads',
      subtitle: 'How boards, the feed and threads look',
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              SettingsGroup(
                title: 'Defaults',
                children: [
                  DashMenuAnchor(
                    menuChildren: [
                      for (final sort in Sort.values)
                        DashMenuEntry(
                          title: sort.title,
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
                  DashMenuAnchor(
                    menuChildren: [
                      DashMenuEntry(
                        title: 'Descending',
                        icon: CupertinoIcons.arrow_down,
                        isSelected:
                            settings.boardSortDirection.value ==
                            SortDirection.desc,
                        onPressed: () =>
                            settings.boardSortDirection.set(SortDirection.desc),
                      ),
                      DashMenuEntry(
                        title: 'Ascending',
                        icon: CupertinoIcons.arrow_up,
                        isSelected:
                            settings.boardSortDirection.value ==
                            SortDirection.asc,
                        onPressed: () =>
                            settings.boardSortDirection.set(SortDirection.asc),
                      ),
                    ],
                    builder: (context, open) => SettingsRow(
                      icon: CupertinoIcons.arrow_up_arrow_down,
                      color: const Color(0xFF34D399),
                      title: 'Direction',
                      value:
                          settings.boardSortDirection.value ==
                              SortDirection.desc
                          ? 'Descending'
                          : 'Ascending',
                      onTap: open,
                    ),
                  ),
                  DashMenuAnchor(
                    menuChildren: [
                      DashMenuEntry(
                        title: 'Grid',
                        icon: CupertinoIcons.square_grid_2x2,
                        isSelected:
                            settings.boardViewMode.value == ViewMode.grid,
                        onPressed: () =>
                            settings.boardViewMode.set(ViewMode.grid),
                      ),
                      DashMenuEntry(
                        title: 'List',
                        icon: CupertinoIcons.list_bullet,
                        isSelected:
                            settings.boardViewMode.value == ViewMode.list,
                        onPressed: () =>
                            settings.boardViewMode.set(ViewMode.list),
                      ),
                    ],
                    builder: (context, open) => SettingsRow(
                      icon: CupertinoIcons.square_grid_2x2_fill,
                      color: DashColors.accent,
                      title: 'Board view',
                      value: settings.boardViewMode.value == ViewMode.grid
                          ? 'Grid'
                          : 'List',
                      onTap: open,
                    ),
                  ),
                ],
              ),
              SettingsGroup(
                title: 'Reading',
                footer:
                    'Nested puts each reply under the post it answers, so '
                    'you can fold whole conversations. Flat lists every post in '
                    'the order it was posted.',
                children: [
                  DashMenuAnchor(
                    menuChildren: [
                      DashMenuEntry(
                        title: 'Nested',
                        icon: CupertinoIcons.list_bullet_indent,
                        isSelected:
                            settings.threadLayout.value == ThreadLayout.nested,
                        onPressed: () =>
                            settings.threadLayout.set(ThreadLayout.nested),
                      ),
                      DashMenuEntry(
                        title: 'Flat',
                        icon: CupertinoIcons.list_bullet,
                        isSelected:
                            settings.threadLayout.value == ThreadLayout.flat,
                        onPressed: () =>
                            settings.threadLayout.set(ThreadLayout.flat),
                      ),
                    ],
                    builder: (context, open) => SettingsRow(
                      icon: CupertinoIcons.list_bullet_indent,
                      color: const Color(0xFF60A5FA),
                      title: 'Thread layout',
                      value: settings.threadLayout.value == ThreadLayout.nested
                          ? 'Nested'
                          : 'Flat',
                      onTap: open,
                    ),
                  ),
                ],
              ),
              SettingsGroup(
                title: 'Playback',
                children: [
                  SettingsRow(
                    icon: CupertinoIcons.speaker_slash_fill,
                    color: const Color(0xFFF472B6),
                    title: 'Start feed videos muted',
                    subtitle:
                        'Videos in the thread feed autoplay without sound',
                    trailing: SettingsSwitch(
                      value: settings.feedVideosStartMuted.value,
                      onChanged: settings.feedVideosStartMuted.set,
                    ),
                  ),
                ],
              ),
              SettingsGroup(
                title: 'Hidden threads',
                footer:
                    'Matching is case-insensitive against the thread title '
                    'and comment, in boards and the feed. Invalid regex is '
                    'treated as a plain keyword.',
                children: [
                  for (final String pattern in settings.hiddenThreadPatterns)
                    SettingsRow(
                      icon: CupertinoIcons.eye_slash_fill,
                      color: DashColors.danger,
                      title: pattern,
                      trailing: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () =>
                            settings.removeHiddenThreadPattern(pattern),
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
                    color: DashColors.accent,
                    title: 'Add filter',
                    subtitle: 'Keyword or regex',
                    onTap: () => _showAddFilter(context, settings),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
