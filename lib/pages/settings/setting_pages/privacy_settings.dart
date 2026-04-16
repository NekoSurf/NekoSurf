import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/pages/settings/cupertino_settings_icon.dart';
import 'package:provider/provider.dart';

class PrivacySettings extends StatefulWidget {
  const PrivacySettings({Key? key}) : super(key: key);

  @override
  State<PrivacySettings> createState() => PrivacySettingsState();
}

class PrivacySettingsState extends State<PrivacySettings> {
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
            'Privacy',
            style: TextStyle(
              color: theme.getTheme() == ThemeData.dark()
                  ? Colors.white
                  : Colors.black,
            ),
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            CupertinoListSection.insetGrouped(
              children: [
                CupertinoListTile(
                  leading: const CupertinoSettingsIcon(
                    icon: CupertinoIcons.exclamationmark_triangle,
                    color: CupertinoColors.systemRed,
                  ),
                  title: const Text('Allow NSFW-Boards'),
                  trailing: CupertinoSwitch(
                    onChanged: (value) => {settings.setNSFW(value)},
                    value: settings.getNSFW(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
