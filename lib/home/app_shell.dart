import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/bookmarks/bookmarks.dart';
import 'package:flutter_chan/home/dashboard.dart';
import 'package:flutter_chan/home/update_prompt.dart';
import 'package:flutter_chan/saved/saved_tab.dart';
import 'package:flutter_chan/settings/settings.dart';
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

  @override
  void initState() {
    super.initState();
    // Needs a Navigator for its dialog, which this is below once it's built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        offerAppUpdate(context);
      }
    });
  }

  void _selectTab(int tab) {
    setState(() {
      _currentTab = tab;
      _builtTabs.add(tab);
    });
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
          bottom: 0,
          child: DashTabBar(
            selectedIndex: _currentTab,
            onSelected: _selectTab,
            tabs: const [
              DashTab(CupertinoIcons.square_grid_2x2_fill, 'Boards'),
              DashTab(CupertinoIcons.paperclip, 'Saved'),
              DashTab(CupertinoIcons.bookmark_fill, 'Bookmarks'),
              DashTab(CupertinoIcons.settings, 'Settings'),
            ],
          ),
        ),
      ],
    );
  }
}
