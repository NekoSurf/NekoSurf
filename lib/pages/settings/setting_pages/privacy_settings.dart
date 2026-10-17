import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/blocs/history_model.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/pages/settings/settings_widgets.dart';
import 'package:flutter_chan/widgets/dash_scaffold.dart';
import 'package:provider/provider.dart';

class PrivacySettings extends StatelessWidget {
  const PrivacySettings({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    return DashScaffold(
      title: 'Privacy',
      subtitle: 'Control what you see',
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              SettingsGroup(
                title: 'Content',
                footer:
                    'Shows boards that are not safe for work in the board list and your feed.',
                children: [
                  SettingsRow(
                    icon: CupertinoIcons.exclamationmark_triangle_fill,
                    color: const Color(0xFFFF5D6C),
                    title: 'Allow NSFW boards',
                    trailing: SettingsSwitch(
                      value: settings.getNSFW(),
                      onChanged: settings.setNSFW,
                    ),
                  ),
                ],
              ),
              SettingsGroup(
                title: 'History',
                footer:
                    'Remembers recently opened threads and boards for the Continue and Recent sections. Turning this off also clears what is stored.',
                children: [
                  SettingsRow(
                    icon: CupertinoIcons.clock_fill,
                    color: const Color(0xFF60A5FA),
                    title: 'Track history',
                    trailing: SettingsSwitch(
                      value: settings.getTrackHistory(),
                      onChanged: (value) {
                        settings.setTrackHistory(value);
                        if (!value) {
                          Provider.of<HistoryProvider>(
                            context,
                            listen: false,
                          ).clear();
                        }
                      },
                    ),
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
