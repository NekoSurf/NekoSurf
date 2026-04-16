import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:provider/provider.dart';

class GridViewSettings extends StatefulWidget {
  const GridViewSettings({Key? key}) : super(key: key);

  @override
  State<GridViewSettings> createState() => GridViewSettingsState();
}

class GridViewSettingsState extends State<GridViewSettings> {
  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeChanger>(context);
    final settings = Provider.of<SettingsProvider>(context);

    return CupertinoPageScaffold(
      backgroundColor: theme.getTheme() == ThemeData.dark()
          ? CupertinoColors.black
          : CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: theme.getTheme() == ThemeData.light()
            ? CupertinoColors.systemGroupedBackground.withValues(alpha: 0.7)
            : CupertinoColors.black.withOpacity(0.7),
        brightness: theme.getTheme() == ThemeData.dark()
            ? Brightness.dark
            : Brightness.light,
        border: Border.all(color: Colors.transparent),
        leading: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(
              MediaQuery.textScaleFactorOf(context),
            ),
          ),
          child: Transform.translate(
            offset: const Offset(-16, 0),
            child: CupertinoNavigationBarBackButton(
              previousPageTitle: 'Threads',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
        middle: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(
              MediaQuery.textScaleFactorOf(context),
            ),
          ),
          child: Text(
            'Thread View',
            style: TextStyle(
              color: theme.getTheme() == ThemeData.dark()
                  ? Colors.white
                  : Colors.black,
            ),
          ),
        ),
      ),
      child: SafeArea(
        child: CupertinoListSection.insetGrouped(
          children: [
            CupertinoListTile(
              title: const Text('Grid View'),
              trailing: settings.getBoardView().name == 'gridView'
                  ? const Icon(CupertinoIcons.check_mark)
                  : Container(),
              onTap: () => {settings.setBoardView(ViewType.gridView)},
            ),
            CupertinoListTile(
              title: const Text('List View'),
              trailing: settings.getBoardView().name == 'gridView'
                  ? Container()
                  : const Icon(CupertinoIcons.check_mark),
              onTap: () => {settings.setBoardView(ViewType.listView)},
            ),
          ],
        ),
      ),
    );
  }
}
