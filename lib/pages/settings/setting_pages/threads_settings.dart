import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:flutter_chan/pages/settings/settings_widgets.dart';
import 'package:flutter_chan/widgets/cupertino_menu.dart';
import 'package:flutter_chan/widgets/dash_dialogs.dart';
import 'package:flutter_chan/widgets/dash_scaffold.dart';
import 'package:provider/provider.dart';

class ThreadsSettings extends StatelessWidget {
  const ThreadsSettings({Key? key}) : super(key: key);

  static void _showAddFilter(
    BuildContext context,
    SettingsProvider settings,
  ) {
    final TextEditingController controller = TextEditingController();
    final bool isDark =
        CupertinoTheme.brightnessOf(context) == Brightness.dark;

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
            CupertinoTextField(
              controller: controller,
              autofocus: true,
              placeholder: r'e.g. crypto|ai slop|\bgeneral\b',
              padding: const EdgeInsets.all(14),
              style: TextStyle(color: DashColors.text(isDark)),
              decoration: BoxDecoration(
                color: DashColors.muted(isDark).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
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
    );
  }

  static String sortName(Sort sort) {
    switch (sort) {
      case Sort.byImagesCount:
        return 'Images';
      case Sort.byBumpOrder:
        return 'Bump order';
      case Sort.byReplyCount:
        return 'Replies';
      case Sort.byNewest:
        return 'Newest';
      case Sort.byOldest:
        return 'Oldest';
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    return DashScaffold(
      title: 'Threads',
      subtitle: 'Defaults for boards and feed',
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              SettingsGroup(
                title: 'Defaults',
                children: [
                  DashMenuAnchor(
                    menuChildren: [
                      for (final sort in [
                        Sort.byImagesCount,
                        Sort.byReplyCount,
                        Sort.byBumpOrder,
                        Sort.byNewest,
                      ])
                        buildMenuItem(
                          title: sortName(sort),
                          isSelected: settings.getBoardSort() == sort,
                          onPressed: () => settings.setBoardSort(sort),
                        ),
                    ],
                    builder: (context, open) => SettingsRow(
                      icon: CupertinoIcons.sort_down,
                      color: const Color(0xFFFB923C),
                      title: 'Sort by',
                      value: sortName(settings.getBoardSort()),
                      onTap: open,
                    ),
                  ),
                  DashMenuAnchor(
                    menuChildren: [
                      buildMenuItem(
                        title: 'Descending',
                        icon: CupertinoIcons.arrow_down,
                        isSelected:
                            settings.getBoardSortDirection() ==
                            SortDirection.desc,
                        onPressed: () =>
                            settings.setBoardSortDirection(SortDirection.desc),
                      ),
                      buildMenuItem(
                        title: 'Ascending',
                        icon: CupertinoIcons.arrow_up,
                        isSelected:
                            settings.getBoardSortDirection() ==
                            SortDirection.asc,
                        onPressed: () =>
                            settings.setBoardSortDirection(SortDirection.asc),
                      ),
                    ],
                    builder: (context, open) => SettingsRow(
                      icon: CupertinoIcons.arrow_up_arrow_down,
                      color: const Color(0xFF34D399),
                      title: 'Direction',
                      value:
                          settings.getBoardSortDirection() == SortDirection.desc
                          ? 'Descending'
                          : 'Ascending',
                      onTap: open,
                    ),
                  ),
                  DashMenuAnchor(
                    menuChildren: [
                      buildMenuItem(
                        title: 'Grid',
                        icon: CupertinoIcons.square_grid_2x2,
                        isSelected:
                            settings.getBoardViewMode() == ViewMode.grid,
                        onPressed: () =>
                            settings.setBoardViewMode(ViewMode.grid),
                      ),
                      buildMenuItem(
                        title: 'List',
                        icon: CupertinoIcons.list_bullet,
                        isSelected:
                            settings.getBoardViewMode() == ViewMode.list,
                        onPressed: () =>
                            settings.setBoardViewMode(ViewMode.list),
                      ),
                    ],
                    builder: (context, open) => SettingsRow(
                      icon: CupertinoIcons.square_grid_2x2_fill,
                      color: DashColors.accent,
                      title: 'Board view',
                      value: settings.getBoardViewMode() == ViewMode.grid
                          ? 'Grid'
                          : 'List',
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
                      value: settings.getFeedVideosStartMuted(),
                      onChanged: settings.setFeedVideosStartMuted,
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
                  for (final String pattern
                      in settings.getHiddenThreadPatterns())
                    SettingsRow(
                      icon: CupertinoIcons.eye_slash_fill,
                      color: DashColors.nsfw,
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
