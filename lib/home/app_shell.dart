import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/home/bookmarks.dart';
import 'package:flutter_chan/home/dashboard.dart';
import 'package:flutter_chan/home/update_prompt.dart';
import 'package:flutter_chan/saved/saved_tab.dart';
import 'package:flutter_chan/settings/settings.dart';
import 'package:flutter_chan/settings/sync_settings.dart';
import 'package:flutter_chan/sync/cloud_sync.dart';
import 'package:flutter_chan/ui/dash_dialogs.dart';
import 'package:flutter_chan/ui/dash_header.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const List<Widget> _tabs = <Widget>[
    Dashboard(),
    SavedTab(),
    Bookmarks(),
    DashScaffold(
      title: 'Settings',
      reserveTabBarSpace: true,
      slivers: [Settings()],
    ),
  ];

  int _currentTab = 0;

  /// Tabs are built on first visit and then kept alive, so switching back
  /// keeps their scroll position and doesn't reload their data.
  final Set<int> _builtTabs = <int>{0};

  static const int _settingsTab = 3;

  final CloudSync _sync = CloudSync.instance;
  bool _showingAlert = false;

  @override
  void initState() {
    super.initState();
    _sync.addListener(_syncChanged);
    // Needs a Navigator for its dialog, which this is below once it's built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        offerAppUpdate(context);
        unawaited(offerCloudSyncOnLaunch(context));
        _syncChanged();
      }
    });
  }

  @override
  void dispose() {
    _sync.removeListener(_syncChanged);
    super.dispose();
  }

  /// Shows what iCloud sync has to say, once, and the dot on Settings.
  void _syncChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    if (_currentTab == _settingsTab) {
      _sync.markNoticeSeen();
    }
    if (_showingAlert) {
      return;
    }
    final ({String title, String message})? alert = _sync.takeAlert();
    if (alert == null) {
      return;
    }
    _showingAlert = true;
    unawaited(
      showDashDialog<void>(
        context: context,
        builder: (dialogContext) => DashDialog(
          title: Text(alert.title),
          content: Text(alert.message),
          actions: [
            DashDialogAction(
              isDefaultAction: true,
              child: const Text('OK'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        ),
      ).whenComplete(() {
        _showingAlert = false;
        _syncChanged();
      }),
    );
  }

  void _selectTab(int tab) {
    setState(() {
      _currentTab = tab;
      _builtTabs.add(tab);
    });
    if (tab == _settingsTab) {
      _sync.markNoticeSeen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IndexedStack(
          index: _currentTab,
          children: [
            for (int tab = 0; tab < _tabs.length; tab++)
              TickerMode(
                enabled: tab == _currentTab,
                child: _builtTabs.contains(tab)
                    ? _tabs[tab]
                    : const SizedBox.shrink(),
              ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.paddingOf(context).bottom + 96,
          child: const Center(child: CloudSyncProgress()),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: DashTabBar(
            selectedIndex: _currentTab,
            onSelected: _selectTab,
            tabs: [
              const DashTab(CupertinoIcons.square_grid_2x2_fill, 'Boards'),
              const DashTab(CupertinoIcons.paperclip, 'Saved'),
              const DashTab(CupertinoIcons.bookmark_fill, 'Bookmarks'),
              DashTab(
                CupertinoIcons.settings,
                'Settings',
                badge: _sync.needsAttention,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
