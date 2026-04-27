import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/constants.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_chan/pages/settings/setting_pages/threads_settings_pages/sort_board_settings.dart';
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
    final theme = Provider.of<ThemeChanger>(context);
    final settings = Provider.of<SettingsProvider>(context);
    final bool isDark = theme.getTheme() == ThemeData.dark();

    return CupertinoPageScaffold(
      backgroundColor: AppColors.pageBackground(isDark),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: AppColors.navigationBackground(isDark),
        brightness: theme.getTheme() == ThemeData.dark()
            ? Brightness.dark
            : Brightness.light,
        leading: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(
              MediaQuery.textScaleFactorOf(context),
            ),
          ),
          child: Transform.translate(
            offset: const Offset(-16, 0),
            child: CupertinoNavigationBarBackButton(
              previousPageTitle: 'Settings',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
        border: Border.all(color: Colors.transparent),
        previousPageTitle: 'Settings',
        middle: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(
              MediaQuery.textScaleFactorOf(context),
            ),
          ),
          child: Text(
            'Threads',
            style: TextStyle(
              color: theme.getTheme() == ThemeData.dark()
                  ? Colors.white
                  : Colors.black,
            ),
          ),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.only(
            top: 8,
            bottom: MediaQuery.of(context).padding.bottom + 16,
          ),
          children: [
            CupertinoListSection.insetGrouped(
              backgroundColor: AppColors.pageBackground(isDark),
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
                CupertinoListTile(
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
                  onTap: () {
                    showCupertinoModalPopup(
                      context: context,
                      builder: (BuildContext context) => CupertinoActionSheet(
                        message: const Text('Default sort direction'),
                        actions: [
                          CupertinoActionSheetAction(
                            child: Text(
                              'Descending',
                              style: settings.getBoardSortDirection() ==
                                      SortDirection.desc
                                  ? const TextStyle(fontWeight: FontWeight.w700)
                                  : const TextStyle(
                                      fontWeight: FontWeight.normal,
                                    ),
                            ),
                            onPressed: () {
                              settings.setBoardSortDirection(SortDirection.desc);
                              Navigator.pop(context);
                            },
                          ),
                          CupertinoActionSheetAction(
                            child: Text(
                              'Ascending',
                              style: settings.getBoardSortDirection() ==
                                      SortDirection.asc
                                  ? const TextStyle(fontWeight: FontWeight.w700)
                                  : const TextStyle(
                                      fontWeight: FontWeight.normal,
                                    ),
                            ),
                            onPressed: () {
                              settings.setBoardSortDirection(SortDirection.asc);
                              Navigator.pop(context);
                            },
                          ),
                        ],
                        cancelButton: CupertinoActionSheetAction(
                          child: const Text('Cancel'),
                          onPressed: () {
                            Navigator.pop(context);
                          },
                        ),
                      ),
                    );
                  },
                ),
                CupertinoListTile(
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
                  onTap: () {
                    showCupertinoModalPopup(
                      context: context,
                      builder: (BuildContext context) => CupertinoActionSheet(
                        message: const Text('Default board view'),
                        actions: [
                          CupertinoActionSheetAction(
                            child: Text(
                              'Grid',
                              style: settings.getBoardViewMode() == ViewMode.grid
                                  ? const TextStyle(fontWeight: FontWeight.w700)
                                  : const TextStyle(
                                      fontWeight: FontWeight.normal,
                                    ),
                            ),
                            onPressed: () {
                              settings.setBoardViewMode(ViewMode.grid);
                              Navigator.pop(context);
                            },
                          ),
                          CupertinoActionSheetAction(
                            child: Text(
                              'List',
                              style: settings.getBoardViewMode() == ViewMode.list
                                  ? const TextStyle(fontWeight: FontWeight.w700)
                                  : const TextStyle(
                                      fontWeight: FontWeight.normal,
                                    ),
                            ),
                            onPressed: () {
                              settings.setBoardViewMode(ViewMode.list);
                              Navigator.pop(context);
                            },
                          ),
                        ],
                        cancelButton: CupertinoActionSheetAction(
                          child: const Text('Cancel'),
                          onPressed: () {
                            Navigator.pop(context);
                          },
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
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
