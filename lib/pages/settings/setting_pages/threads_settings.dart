import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/constants.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../cupertino_settings_icon.dart';

class ThreadsSettings extends ConsumerWidget {
  const ThreadsSettings({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return GlassScaffold(
      backgroundColor: AppColors.pageBackground(
        Theme.of(context).brightness == Brightness.dark,
      ),
      appBar: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: GlassAppBar(
          title: Text(
            'Threads',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ),
          leading: GlassButton(
            icon: const Icon(CupertinoIcons.back),
            onTap: () => Navigator.of(context).pop(),
            width: 40,
            height: 40,
            iconSize: 20,
          ),
        ),
      ),
      extendBody: false,
      body: CupertinoListSection.insetGrouped(
        backgroundColor: Colors.transparent,
        children: [
          GlassMenu(
            menuAlignment: GlassMenuAlignment.center,
            autoAdjustToScreen: true,
            menuWidth: MediaQuery.of(context).size.width * 0.8,
            items: [
              GlassMenuItem(
                title: 'Images Count',
                icon: const Icon(CupertinoIcons.photo_on_rectangle),
                isDestructive: false,
                onTap: () => ref
                    .read(settingsProvider.notifier)
                    .setBoardSort(Sort.byImagesCount),
                trailing: settings.getBoardSort().name == 'byImagesCount'
                    ? const Icon(CupertinoIcons.check_mark)
                    : null,
              ),
              GlassMenuItem(
                title: 'Reply Count',
                icon: const Icon(CupertinoIcons.bubble_left_bubble_right),
                isDestructive: false,
                onTap: () => ref
                    .read(settingsProvider.notifier)
                    .setBoardSort(Sort.byReplyCount),
                trailing: settings.getBoardSort().name == 'byReplyCount'
                    ? const Icon(CupertinoIcons.check_mark)
                    : null,
              ),
              GlassMenuItem(
                title: 'Bump Order',
                icon: const Icon(CupertinoIcons.arrow_up_arrow_down),
                isDestructive: false,
                onTap: () => ref
                    .read(settingsProvider.notifier)
                    .setBoardSort(Sort.byBumpOrder),
                trailing: settings.getBoardSort().name == 'byBumpOrder'
                    ? const Icon(CupertinoIcons.check_mark)
                    : null,
              ),
              GlassMenuItem(
                title: 'Newest',
                icon: const Icon(CupertinoIcons.clock),
                isDestructive: false,
                onTap: () => ref
                    .read(settingsProvider.notifier)
                    .setBoardSort(Sort.byNewest),
                trailing: settings.getBoardSort().name == 'byNewest'
                    ? const Icon(CupertinoIcons.check_mark)
                    : null,
              ),
            ],
            triggerBuilder: (ctx, toggle) => AdaptiveLiquidGlassLayer(
              child: CupertinoListTile(
                leading: const CupertinoSettingsIcon(
                  icon: CupertinoIcons.sort_down,
                  color: CupertinoColors.systemOrange,
                ),
                title: const Text('Default board sort'),
                trailing: Text(
                  getSortByName(settings.getBoardSort()),
                  style: const TextStyle(color: CupertinoColors.inactiveGray),
                ),
                onTap: toggle,
              ),
            ),
          ),
          GlassMenu(
            menuAlignment: GlassMenuAlignment.center,
            autoAdjustToScreen: true,
            menuWidth: MediaQuery.of(context).size.width * 0.8,
            items: [
              GlassMenuItem(
                title: 'Descending',
                icon: const Icon(CupertinoIcons.arrow_down),
                isDestructive: false,
                onTap: () => ref
                    .read(settingsProvider.notifier)
                    .setBoardSortDirection(SortDirection.desc),
                trailing: settings.getBoardSortDirection() == SortDirection.desc
                    ? const Icon(CupertinoIcons.check_mark)
                    : null,
              ),
              GlassMenuItem(
                title: 'Ascending',
                icon: const Icon(CupertinoIcons.arrow_up),
                isDestructive: false,
                onTap: () => ref
                    .read(settingsProvider.notifier)
                    .setBoardSortDirection(SortDirection.asc),
                trailing: settings.getBoardSortDirection() == SortDirection.asc
                    ? const Icon(CupertinoIcons.check_mark)
                    : null,
              ),
            ],
            triggerBuilder: (ctx, toggle) => AdaptiveLiquidGlassLayer(
              child: CupertinoListTile(
                leading: const CupertinoSettingsIcon(
                  icon: CupertinoIcons.arrow_up_arrow_down,
                  color: CupertinoColors.systemGreen,
                ),
                title: const Text('Default sort direction'),
                trailing: Text(
                  settings.getBoardSortDirection() == SortDirection.desc
                      ? 'Descending'
                      : 'Ascending',
                  style: const TextStyle(color: CupertinoColors.inactiveGray),
                ),
                onTap: toggle,
              ),
            ),
          ),
          GlassMenu(
            menuAlignment: GlassMenuAlignment.center,
            autoAdjustToScreen: true,
            menuWidth: MediaQuery.of(context).size.width * 0.8,
            items: [
              GlassMenuItem(
                title: 'Grid',
                icon: const Icon(CupertinoIcons.square_grid_2x2),
                isDestructive: false,
                onTap: () => ref
                    .read(settingsProvider.notifier)
                    .setBoardViewMode(ViewMode.grid),
                trailing: settings.getBoardViewMode() == ViewMode.grid
                    ? const Icon(CupertinoIcons.check_mark)
                    : null,
              ),
              GlassMenuItem(
                title: 'List',
                icon: const Icon(CupertinoIcons.list_bullet),
                isDestructive: false,
                onTap: () => ref
                    .read(settingsProvider.notifier)
                    .setBoardViewMode(ViewMode.list),
                trailing: settings.getBoardViewMode() == ViewMode.list
                    ? const Icon(CupertinoIcons.check_mark)
                    : null,
              ),
            ],
            triggerBuilder: (ctx, toggle) => AdaptiveLiquidGlassLayer(
              child: CupertinoListTile(
                leading: const CupertinoSettingsIcon(
                  icon: CupertinoIcons.square_grid_2x2,
                  color: CupertinoColors.activeBlue,
                ),
                title: const Text('Default board view'),
                trailing: Text(
                  settings.getBoardViewMode() == ViewMode.grid
                      ? 'Grid'
                      : 'List',
                  style: const TextStyle(color: CupertinoColors.inactiveGray),
                ),
                onTap: toggle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String getSortByName(Sort sort) {
    switch (sort) {
      case Sort.byImagesCount:
        return 'Images Count';
      case Sort.byBumpOrder:
        return 'Bump Order';
      case Sort.byReplyCount:
        return 'Reply Count';
      case Sort.byNewest:
        return 'Newest';
      case Sort.byOldest:
        return 'Oldest';
    }
  }
}
