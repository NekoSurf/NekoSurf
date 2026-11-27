import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_header.dart';
import 'package:flutter_chan/ui/keys.dart';
import 'package:flutter_chan/ui/pull_to_refresh.dart';
import 'package:flutter_chan/ui/scrollbars.dart';
import 'package:flutter_chan/ui/status_bar_tap.dart';
import 'package:flutter_chan/ui/window_size.dart';

class DashScaffold extends StatefulWidget {
  const DashScaffold({
    super.key,
    required this.title,
    required this.slivers,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.onRefresh,
    this.onFind,
    this.reserveTabBarSpace = false,
    this.readable = false,
  });

  final String title;

  final String? subtitle;
  final Widget? leading;
  final List<Widget> slivers;

  /// Leaves room at the bottom for a tab bar drawn by the parent.
  final bool reserveTabBarSpace;

  /// Keeps [slivers] to a readable column in a wide window (see
  /// [kReadableWidth]), for a page of rows and text; grids take the width.
  final bool readable;
  final List<Widget> actions;
  final Future<void> Function()? onRefresh;

  /// Goes to the page's search field: ⌘F with a keyboard, as ⌘R refreshes.
  final VoidCallback? onFind;

  @override
  State<DashScaffold> createState() => _DashScaffoldState();
}

class _DashScaffoldState extends State<DashScaffold> {
  bool _elevated = false;

  /// How far the list is scrolled, so the tinted top goes up with it.
  final ValueNotifier<double> _scrolled = ValueNotifier<double>(0);

  @override
  void dispose() {
    _scrolled.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) {
      return false;
    }
    _scrolled.value = n.metrics.pixels;
    final bool elevated = n.metrics.pixels > 6;
    if (elevated != _elevated) {
      setState(() => _elevated = elevated);
    }
    return false;
  }

  Widget _refreshable(double topInset, Widget list) {
    final Future<void> Function()? onRefresh = widget.onRefresh;
    if (onRefresh == null) {
      return list;
    }
    return PullToRefresh(onRefresh: onRefresh, topInset: topInset, child: list);
  }

  @override
  Widget build(BuildContext context) {
    final double top = MediaQuery.paddingOf(context).top;
    final double bottom = MediaQuery.paddingOf(context).bottom;
    final double barSpace =
        !widget.reserveTabBarSpace || !DashTabBarScope.atBottomOf(context)
        ? 0
        : kDashTabBarHeight + (bottom > 0 ? bottom : 12) + 12;

    final Future<void> Function()? onRefresh = widget.onRefresh;
    final VoidCallback? onFind = widget.onFind;
    // The list scrolls with its route's or tab's controller.
    final Widget page = StatusBarTap(
      onTap: () => scrollToTop(PrimaryScrollController.maybeOf(context)),
      child: Material(
        color: DashColors.page(context),
        child: Stack(
          children: [
            // The top of the page, tinted with the theme's colours and fading
            // into it, scrolling away with the list.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: top + kDashHeaderHeight + 320,
              child: IgnorePointer(
                child: ValueListenableBuilder<double>(
                  valueListenable: _scrolled,
                  // Pulled down, it stays put rather than come off the top.
                  builder: (context, scrolled, child) => Transform.translate(
                    offset: Offset(0, scrolled > 0 ? -scrolled : 0),
                    child: child,
                  ),
                  child: _Wash(isDark: context.isDark),
                ),
              ),
            ),
            _refreshable(
              top + kDashHeaderHeight,
              NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: PageScrollbar(
                  // Below the header, and above the tab bar.
                  padding: MediaQuery.paddingOf(context).copyWith(
                    top: top + kDashHeaderHeight,
                    bottom: bottom + barSpace,
                  ),
                  child: CustomScrollView(
                    primary: true,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    physics: widget.onRefresh == null
                        ? null
                        : PullToRefresh.pullPhysics,
                    slivers: [
                      SliverToBoxAdapter(
                        child: SizedBox(height: top + kDashHeaderHeight + 8),
                      ),
                      for (final Widget sliver in widget.slivers)
                        if (widget.readable)
                          ReadableSliver(sliver: sliver)
                        else
                          sliver,
                      SliverToBoxAdapter(
                        child: SizedBox(height: bottom + 24 + barSpace),
                      ),
                    ],
                  ),
                ),
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
                elevated: _elevated || DashHeaderLine.alwaysOf(context),
              ),
            ),
          ],
        ),
      ),
    );
    if (onRefresh == null && onFind == null) {
      return page;
    }
    return PageKeys(
      bindings: keyBindings({
        if (onRefresh != null)
          withCommand(LogicalKeyboardKey.keyR): () => onRefresh(),
        withCommand(LogicalKeyboardKey.keyF): ?onFind,
      }),
      child: page,
    );
  }
}

class _Wash extends StatelessWidget {
  const _Wash({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            context.accent.withValues(alpha: isDark ? 0.28 : 0.3),
            context.accent2.withValues(alpha: 0.12),
            context.accent2.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ),
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
    this.onScrollToTop,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;

  /// Takes [body] to its top when the status bar is tapped. Without it, the
  /// list scrolling with the route's controller goes up.
  final VoidCallback? onScrollToTop;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return StatusBarTap(
      onTap:
          onScrollToTop ??
          () => scrollToTop(PrimaryScrollController.maybeOf(context)),
      child: Material(
        color: DashColors.page(context),
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
      ),
    );
  }
}
