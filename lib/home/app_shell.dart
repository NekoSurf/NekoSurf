import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/bookmarks/bookmarks_model.dart';
import 'package:flutter_chan/home/bookmarks.dart';
import 'package:flutter_chan/home/dashboard.dart';
import 'package:flutter_chan/home/update_prompt.dart';
import 'package:flutter_chan/saved/saved_tab.dart';
import 'package:flutter_chan/settings/settings.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/settings/sync_settings.dart';
import 'package:flutter_chan/sync/cloud_sync.dart';
import 'package:flutter_chan/ui/dash_dialogs.dart';
import 'package:flutter_chan/ui/dash_header.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';
import 'package:provider/provider.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

/// The app's tabs, in the tab bar's order.
enum _Tab { boards, saved, bookmarks, settings }

class _AppShellState extends State<AppShell> {
  static const Map<_Tab, Widget> _pages = <_Tab, Widget>{
    _Tab.boards: Dashboard(),
    _Tab.saved: SavedTab(),
    _Tab.bookmarks: Bookmarks(),
    _Tab.settings: DashScaffold(
      title: 'Settings',
      reserveTabBarSpace: true,
      slivers: [Settings()],
    ),
  };

  _Tab _currentTab = _Tab.boards;

  /// Tabs are built on first visit and then kept alive, so switching back
  /// keeps their scroll position and doesn't reload their data. Bookmarks
  /// is built at once, so its tab can show how many threads have new
  /// replies.
  final Set<_Tab> _builtTabs = <_Tab>{_Tab.boards, _Tab.bookmarks};

  /// Each tab's own, so tapping the tab shown takes just it to the top.
  final Map<_Tab, ScrollController> _scrolls = <_Tab, ScrollController>{
    for (final _Tab tab in _Tab.values) tab: ScrollController(),
  };

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
    for (final ScrollController scroll in _scrolls.values) {
      scroll.dispose();
    }
    _sync.removeListener(_syncChanged);
    super.dispose();
  }

  /// Shows what iCloud sync has to say, once, and the dot on Settings.
  void _syncChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    if (_currentTab == _Tab.settings) {
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

  void _selectTab(_Tab tab) {
    if (tab == _currentTab) {
      _scrollToTop(_scrolls[tab]!);
      return;
    }
    setState(() {
      _currentTab = tab;
      _builtTabs.add(tab);
    });
    if (tab == _Tab.settings) {
      _sync.markNoticeSeen();
    }
  }

  void _scrollToTop(ScrollController scroll) {
    if (scroll.hasClients && scroll.offset > 0) {
      scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ValueNotifier<int> withNewReplies = Provider.of<BookmarksProvider>(
      context,
      listen: false,
    ).withNewReplies;
    // Without its tab, Saved opens from History.
    final List<_Tab> shown = [
      for (final _Tab tab in _Tab.values)
        if (tab != _Tab.saved ||
            context.select<SettingsProvider, bool>(
              (settings) => settings.showSavedTab.value,
            ))
          tab,
    ];
    final _Tab current = shown.contains(_currentTab)
        ? _currentTab
        : _Tab.boards;

    return Stack(
      children: [
        // Every tab keeps its place, shown in the tab bar or not: the stack
        // goes by position, so the others keep their state when Saved goes.
        IndexedStack(
          index: current.index,
          children: [
            for (final _Tab tab in _Tab.values)
              TickerMode(
                enabled: tab == current,
                child: _builtTabs.contains(tab) && shown.contains(tab)
                    // A page's list scrolls with the controller it's given.
                    ? PrimaryScrollController(
                        controller: _scrolls[tab]!,
                        child: _pages[tab]!,
                      )
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
          child: ValueListenableBuilder<int>(
            valueListenable: withNewReplies,
            builder: (context, newReplies, _) => DashTabBar(
              selectedIndex: shown.indexOf(current),
              onSelected: (int index) => _selectTab(shown[index]),
              tabs: [
                for (final _Tab tab in shown)
                  switch (tab) {
                    _Tab.boards => const DashTab(
                      CupertinoIcons.square_grid_2x2_fill,
                      'Boards',
                    ),
                    _Tab.saved => const DashTab(
                      CupertinoIcons.paperclip,
                      'Saved',
                    ),
                    _Tab.bookmarks => DashTab(
                      CupertinoIcons.bookmark_fill,
                      'Bookmarks',
                      count: newReplies,
                    ),
                    _Tab.settings => DashTab(
                      CupertinoIcons.settings,
                      'Settings',
                      badge: _sync.needsAttention,
                    ),
                  },
              ],
            ),
          ),
        ),
      ],
    );
  }
}
