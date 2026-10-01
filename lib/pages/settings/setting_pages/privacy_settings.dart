import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/constants.dart';
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
    final settings = Provider.of<SettingsProvider>(context);

    return CupertinoPageScaffold(
      backgroundColor: AppColors.pageBackground(
        Theme.of(context).brightness == Brightness.dark,
      ),
      navigationBar: const CupertinoNavigationBar(middle: Text('Privacy')),
      child: ListView(
        children: [
          CupertinoListSection.insetGrouped(
            backgroundColor: Colors.transparent,
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
    );
  }
}
