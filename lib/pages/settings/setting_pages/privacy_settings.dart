import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/constants.dart';
import 'package:flutter_chan/pages/settings/cupertino_settings_icon.dart';
import 'package:liquid_glass_widgets/widgets/interactive/glass_button.dart';
import 'package:liquid_glass_widgets/widgets/surfaces/glass_app_bar.dart';
import 'package:liquid_glass_widgets/widgets/surfaces/glass_scaffold.dart';
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

    return GlassScaffold(
      backgroundColor: AppColors.pageBackground(
        Theme.of(context).brightness == Brightness.dark,
      ),
      appBar: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: GlassAppBar(
          title: Text(
            'Privacy',
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
    );
  }
}
