import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/constants.dart';
import 'package:flutter_chan/widgets/dash_header.dart';

class DashScaffold extends StatefulWidget {
  const DashScaffold({
    super.key,
    required this.title,
    required this.slivers,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.bottomBar,
    this.onRefresh,
    this.keyboardDismiss = false,
    this.reserveTabBarSpace = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> slivers;

  /// Leaves room at the bottom for a tab bar drawn by the parent.
  final bool reserveTabBarSpace;
  final List<Widget> actions;
  final Widget? bottomBar;
  final Future<void> Function()? onRefresh;
  final bool keyboardDismiss;

  @override
  State<DashScaffold> createState() => _DashScaffoldState();
}

class _DashScaffoldState extends State<DashScaffold> {
  bool _elevated = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) {
      return false;
    }
    final bool elevated = n.metrics.pixels > 6;
    if (elevated != _elevated) {
      setState(() => _elevated = elevated);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final double top = MediaQuery.paddingOf(context).top;
    final double bottom = MediaQuery.paddingOf(context).bottom;
    final double barSpace =
        widget.bottomBar == null && !widget.reserveTabBarSpace
        ? 0
        : kDashTabBarHeight + (bottom > 0 ? bottom : 12) + 12;

    return Material(
      color: AppColors.pageBackground(isDark),
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: CustomScrollView(
              keyboardDismissBehavior: widget.keyboardDismiss
                  ? ScrollViewKeyboardDismissBehavior.onDrag
                  : ScrollViewKeyboardDismissBehavior.manual,
              slivers: [
                if (widget.onRefresh != null)
                  CupertinoSliverRefreshControl(onRefresh: widget.onRefresh),
                SliverToBoxAdapter(
                  child: SizedBox(height: top + kDashHeaderHeight + 8),
                ),
                ...widget.slivers,
                SliverToBoxAdapter(
                  child: SizedBox(height: bottom + 24 + barSpace),
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: DashHeader(
              title: widget.title,
              subtitle: widget.subtitle,
              leading: widget.leading,
              showBack: ModalRoute.of(context)?.canPop ?? false,
              actions: widget.actions,
              elevated: _elevated,
            ),
          ),
          if (widget.bottomBar != null)
            Positioned(left: 0, right: 0, bottom: 0, child: widget.bottomBar!),
        ],
      ),
    );
  }
}

/// Custom header around a non-sliver body (e.g. the thread list).
class DashBarScaffold extends StatelessWidget {
  const DashBarScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final media = MediaQuery.of(context);

    return Material(
      color: AppColors.pageBackground(isDark),
      child: Stack(
        children: [
          // Children keep using paddingOf(context).top to clear the header.
          MediaQuery(
            data: media.copyWith(
              padding: media.padding.copyWith(
                top: media.padding.top + kDashHeaderHeight,
              ),
            ),
            child: body,
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: DashHeader(
              title: title,
              subtitle: subtitle,
              showBack: ModalRoute.of(context)?.canPop ?? false,
              actions: actions,
              elevated: true,
            ),
          ),
        ],
      ),
    );
  }
}
