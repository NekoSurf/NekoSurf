import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/history/history_model.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/settings/settings_widgets.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';
import 'package:provider/provider.dart';

class PrivacySettings extends StatelessWidget {
  const PrivacySettings({super.key});

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
                    color: DashColors.danger,
                    title: 'Allow NSFW boards',
                    trailing: SettingsSwitch(
                      value: settings.allowNSFW.value,
                      onChanged: settings.allowNSFW.set,
                    ),
                  ),
                ],
              ),
              SettingsGroup(
                title: 'History',
                footer:
                    'Lists the threads you have opened on the History page. Turning this off also clears what is stored.',
                children: [
                  SettingsRow(
                    icon: CupertinoIcons.clock_fill,
                    color: const Color(0xFF60A5FA),
                    title: 'Track history',
                    trailing: SettingsSwitch(
                      value: settings.trackHistory.value,
                      onChanged: Provider.of<HistoryProvider>(
                        context,
                        listen: false,
                      ).setTracking,
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
