import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/constants.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_chan/widgets/cupertino_menu.dart';
import 'package:provider/provider.dart';

import '../cupertino_settings_icon.dart';

class ThreadsSettings extends StatefulWidget {
  const ThreadsSettings({Key? key}) : super(key: key);

  @override
  State<ThreadsSettings> createState() => ThreadsSettingsState();
}

class ThreadsSettingsState extends State<ThreadsSettings> {
  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    return CupertinoPageScaffold(
      backgroundColor: AppColors.pageBackground(
        Theme.of(context).brightness == Brightness.dark,
      ),
      navigationBar: const CupertinoNavigationBar(middle: Text('Threads')),
      child: ListView(
        children: [
          CupertinoListSection.insetGrouped(
            backgroundColor: Colors.transparent,
            children: [
              CupertinoMenuAnchor(
                menuChildren: [
                  for (final sort in [
                    Sort.byImagesCount,
                    Sort.byReplyCount,
                    Sort.byBumpOrder,
                    Sort.byNewest,
                  ])
                    buildMenuItem(
                      title: getSortByName(sort),
                      isSelected: settings.getBoardSort() == sort,
                      onPressed: () => settings.setBoardSort(sort),
                    ),
                ],
                builder: (context, controller, _) => CupertinoListTile(
                  leading: const CupertinoSettingsIcon(
                    icon: CupertinoIcons.sort_down,
                    color: CupertinoColors.systemOrange,
                  ),
                  title: const Text('Default board sort'),
                  trailing: Text(
                    getSortByName(settings.getBoardSort()),
                    style: const TextStyle(color: CupertinoColors.inactiveGray),
                  ),
                  onTap: controller.open,
                ),
              ),
              CupertinoMenuAnchor(
                menuChildren: [
                  buildMenuItem(
                    title: 'Descending',
                    icon: CupertinoIcons.arrow_down,
                    isSelected:
                        settings.getBoardSortDirection() == SortDirection.desc,
                    onPressed: () =>
                        settings.setBoardSortDirection(SortDirection.desc),
                  ),
                  buildMenuItem(
                    title: 'Ascending',
                    icon: CupertinoIcons.arrow_up,
                    isSelected:
                        settings.getBoardSortDirection() == SortDirection.asc,
                    onPressed: () =>
                        settings.setBoardSortDirection(SortDirection.asc),
                  ),
                ],
                builder: (context, controller, _) => CupertinoListTile(
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
                  onTap: controller.open,
                ),
              ),
              CupertinoMenuAnchor(
                menuChildren: [
                  buildMenuItem(
                    title: 'Grid',
                    icon: CupertinoIcons.square_grid_2x2,
                    isSelected: settings.getBoardViewMode() == ViewMode.grid,
                    onPressed: () => settings.setBoardViewMode(ViewMode.grid),
                  ),
                  buildMenuItem(
                    title: 'List',
                    icon: CupertinoIcons.list_bullet,
                    isSelected: settings.getBoardViewMode() == ViewMode.list,
                    onPressed: () => settings.setBoardViewMode(ViewMode.list),
                  ),
                ],
                builder: (context, controller, _) => CupertinoListTile(
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
                  onTap: controller.open,
                ),
              ),
            ],
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
