import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/constants.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';

const double kDashHeaderHeight = 62;
const double kDashTabBarHeight = 64;

class DashIconButton extends StatefulWidget {
  const DashIconButton({Key? key, required this.icon, required this.onPressed})
    : super(key: key);

  final Widget icon;
  final VoidCallback? onPressed;

  @override
  State<DashIconButton> createState() => _DashIconButtonState();
}

class _DashIconButtonState extends State<DashIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: 40,
          height: 40,
          margin: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(
            color: DashColors.card(isDark),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: DashColors.border(isDark)),
          ),
          alignment: Alignment.center,
          child: IconTheme(
            data: IconThemeData(color: DashColors.text(isDark), size: 19),
            child: widget.icon,
          ),
        ),
      ),
    );
  }
}

class DashHeader extends StatelessWidget {
  const DashHeader({
    Key? key,
    required this.title,
    this.subtitle,
    this.leading,
    this.showBack = false,
    this.actions = const [],
    this.elevated = false,
  }) : super(key: key);

  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool showBack;
  final List<Widget> actions;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final bool isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final double top = MediaQuery.paddingOf(context).top;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: EdgeInsets.fromLTRB(16, top + 8, 12, 10),
          decoration: BoxDecoration(
            color: AppColors.pageBackground(isDark).withValues(alpha: 0.82),
            border: Border(
              bottom: BorderSide(
                color: elevated
                    ? DashColors.accent.withValues(alpha: 0.18)
                    : Colors.transparent,
              ),
            ),
          ),
          child: SizedBox(
            height: kDashHeaderHeight - 18,
            child: Row(
              children: [
                if (showBack)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: DashColors.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        CupertinoIcons.chevron_left,
                        size: 18,
                        color: DashColors.accent,
                      ),
                    ),
                  )
                else if (leading != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: leading,
                  ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 21,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          color: DashColors.text(isDark),
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: DashColors.muted(isDark),
                          ),
                        ),
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DashTab {
  const DashTab(this.icon, this.label);

  final IconData icon;
  final String label;
}

class DashTabBar extends StatelessWidget {
  const DashTabBar({
    Key? key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  }) : super(key: key);

  final List<DashTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final bool isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final double bottom = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom > 0 ? bottom : 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            height: kDashTabBarHeight,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: DashColors.card(isDark).withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: DashColors.border(isDark)),
            ),
            child: Row(
              children: [
                for (int i = 0; i < tabs.length; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onSelected(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          gradient: i == selectedIndex
                              ? LinearGradient(
                                  colors: [
                                    DashColors.accent.withValues(alpha: 0.24),
                                    DashColors.accent2.withValues(alpha: 0.2),
                                  ],
                                )
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              tabs[i].icon,
                              size: 21,
                              color: i == selectedIndex
                                  ? DashColors.accent
                                  : DashColors.muted(isDark),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tabs[i].label,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: i == selectedIndex
                                    ? DashColors.text(isDark)
                                    : DashColors.muted(isDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
