import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/blocs/history_model.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/blocs/watched_posts_model.dart';
import 'package:flutter_chan/pages/settings/settings_widgets.dart';
import 'package:flutter_chan/services/show_snackbar.dart';
import 'package:flutter_chan/widgets/cupertino_menu.dart';
import 'package:flutter_chan/widgets/dash_dialogs.dart';
import 'package:flutter_chan/widgets/dash_scaffold.dart';
import 'package:provider/provider.dart';

class DataSettings extends StatelessWidget {
  const DataSettings({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    return DashScaffold(
      title: 'Data',
      subtitle: 'Reading progress and history',
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              SettingsGroup(
                title: 'Reading',
                children: [
                  SettingsRow(
                    icon: CupertinoIcons.arrow_down_circle_fill,
                    color: const Color(0xFF60A5FA),
                    title: 'Auto-scroll to last seen',
                    subtitle: 'Jump to the last media you viewed in a thread',
                    trailing: SettingsSwitch(
                      value: settings.getAutoScrollToLastSeen(),
                      onChanged: settings.setAutoScrollToLastSeen,
                    ),
                  ),
                ],
              ),
              SettingsGroup(
                title: 'Storage',
                footer:
                    'Watched status of posts is kept for the selected number of days.',
                children: [
                  DashMenuAnchor(
                    menuChildren: [
                      for (final days in [3, 7, 14, 30])
                        buildMenuItem(
                          title: '$days days',
                          icon: CupertinoIcons.clock,
                          isSelected:
                              settings.getWatchedPostsRetentionDays() == days,
                          onPressed: () =>
                              settings.setWatchedPostsRetentionDays(days),
                        ),
                    ],
                    builder: (context, open) => SettingsRow(
                      icon: CupertinoIcons.timer,
                      color: const Color(0xFFFBBF24),
                      title: 'Watched posts retention',
                      value: '${settings.getWatchedPostsRetentionDays()} days',
                      onTap: open,
                    ),
                  ),
                  SettingsRow(
                    icon: CupertinoIcons.eye_slash_fill,
                    color: const Color(0xFFFF5D6C),
                    title: 'Clear watched posts',
                    destructive: true,
                    onTap: () async {
                      await Provider.of<WatchedPostsProvider>(
                        context,
                        listen: false,
                      ).clearAllWatchedPosts();
                      if (context.mounted) {
                        showCupertinoSnackbar(
                          const Duration(milliseconds: 1800),
                          true,
                          context,
                          'Watched posts history cleared!',
                        );
                      }
                    },
                  ),
                  SettingsRow(
                    icon: CupertinoIcons.clock_fill,
                    color: const Color(0xFFFF5D6C),
                    title: 'Clear recently visited',
                    destructive: true,
                    onTap: () async {
                      await Provider.of<HistoryProvider>(
                        context,
                        listen: false,
                      ).clear();
                      if (context.mounted) {
                        showCupertinoSnackbar(
                          const Duration(milliseconds: 1800),
                          true,
                          context,
                          'Recent history cleared!',
                        );
                      }
                    },
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
