import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/constants.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_chan/pages/settings/setting_pages/threads_settings_pages/sort_board_settings.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
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
          CupertinoListTile(
            leading: const CupertinoSettingsIcon(
              icon: CupertinoIcons.sort_down,
              color: CupertinoColors.systemOrange,
            ),
            title: const Text('Default board sort'),
            trailing: Text(
              getSortByName(settings.getBoardSort()),
              style: const TextStyle(color: CupertinoColors.inactiveGray),
            ),
            onTap: () => {
              Navigator.of(context).push(
                CupertinoPageRoute(
                  builder: (context) => const SortBoardSettings(),
                ),
              ),
            },
          ),
          GlassMenu(
            menuAlignment: GlassMenuAlignment.center,
            autoAdjustToScreen: true,
            items: [
              GlassMenuItem(
                title: 'Descending',
                icon: const Icon(CupertinoIcons.arrow_down),
                isDestructive: false,
                onTap: () => settings.setBoardSortDirection(SortDirection.desc),
              ),
              GlassMenuItem(
                title: 'Ascending',
                icon: const Icon(CupertinoIcons.arrow_up),
                isDestructive: false,
                onTap: () => settings.setBoardSortDirection(SortDirection.asc),
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
            items: [
              GlassMenuItem(
                title: 'Grid',
                icon: const Icon(CupertinoIcons.square_grid_2x2),
                isDestructive: false,
                onTap: () => settings.setBoardViewMode(ViewMode.grid),
              ),
              GlassMenuItem(
                title: 'List',
                icon: const Icon(CupertinoIcons.list_bullet),
                isDestructive: false,
                onTap: () => settings.setBoardViewMode(ViewMode.list),
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
