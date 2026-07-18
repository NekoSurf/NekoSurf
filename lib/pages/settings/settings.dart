import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/pages/settings/setting_pages/data_settings.dart';
import 'package:flutter_chan/pages/settings/setting_pages/privacy_settings.dart';
import 'package:flutter_chan/pages/settings/setting_pages/threads_settings.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'cupertino_settings_icon.dart';

class Settings extends StatefulWidget {
  const Settings({Key? key}) : super(key: key);

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  late Future<PackageInfo> _getVersionNumber;
  @override
  void initState() {
    super.initState();

    _getVersionNumber = getVersionNumber();
  }

  Future<PackageInfo> getVersionNumber() async {
    final PackageInfo info = await PackageInfo.fromPlatform();

    return info;
  }

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: CupertinoListSection.insetGrouped(
        backgroundColor: Colors.transparent,
        children: [
          CupertinoListTile(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            leadingSize: 60,
            leading: Image.asset('assets/icons/icon-round.png'),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('NekoSurf'),
                FutureBuilder<PackageInfo>(
                  future: _getVersionNumber,
                  builder: (context, AsyncSnapshot<PackageInfo> snapshot) {
                    final version = snapshot.hasData
                        ? '${snapshot.data!.version}+${snapshot.data!.buildNumber}'
                        : '';
                    return Text(
                      version,
                      style: const TextStyle(
                        color: CupertinoColors.systemGrey,
                        fontSize: 15,
                      ),
                    );
                  },
                ),
              ],
            ),
            trailing: const CupertinoListTileChevron(),
            onTap: () => {launchURL('https://github.com/NekoSurf/NekoSurf')},
          ),
          CupertinoListTile(
            leading: const CupertinoSettingsIcon(
              icon: CupertinoIcons.list_bullet,
              color: CupertinoColors.systemPurple,
            ),
            title: const Text('Threads'),
            onTap: () => {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ThreadsSettings(),
                ),
              ),
            },
            trailing: const CupertinoListTileChevron(),
          ),
          CupertinoListTile(
            leading: const CupertinoSettingsIcon(
              icon: CupertinoIcons.hand_raised_fill,
              color: CupertinoColors.activeGreen,
            ),
            title: const Text('Privacy'),
            onTap: () => {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const PrivacySettings(),
                ),
              ),
            },
            trailing: const CupertinoListTileChevron(),
          ),
          CupertinoListTile(
            leading: const CupertinoSettingsIcon(
              icon: CupertinoIcons.doc,
              color: CupertinoColors.systemYellow,
            ),
            title: const Text('Data'),
            onTap: () => {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const DataSettings()),
              ),
            },
            trailing: const CupertinoListTileChevron(),
          ),
        ],
      ),
    );
  }
}
