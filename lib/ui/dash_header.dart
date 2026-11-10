import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/frosted.dart';

const double kDashHeaderHeight = 62;
const double kDashTabBarHeight = 64;

class DashIconButton extends StatefulWidget {
  const DashIconButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  /// What it does, for VoiceOver.
  final String label;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  State<DashIconButton> createState() => _DashIconButtonState();
}

class _DashIconButtonState extends State<DashIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;

    return Semantics(
      label: widget.label,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed ? 0.9 : 1,
          duration: const Duration(milliseconds: 100),
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: SizedBox.square(
              dimension: 40,
              child: Frosted(
                radius: 14,
                blur: 16,
                color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.55),
                borderColor: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08),
                child: Center(
                  child: IconTheme(
                    data: IconThemeData(
                      color: DashColors.text(isDark),
                      size: 19,
                    ),
                    child: widget.icon,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DashHeader extends StatelessWidget {
  const DashHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.showBack = false,
    this.actions = const [],
    this.elevated = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool showBack;
  final List<Widget> actions;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;
    final double top = MediaQuery.paddingOf(context).top;

    // Like the tab bar, its text is sized to fit: it doesn't grow.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: EdgeInsets.fromLTRB(16, top + 8, 12, 10),
            decoration: BoxDecoration(
              color: DashColors.page(isDark).withValues(alpha: 0.82),
              border: Border(
                bottom: BorderSide(
                  color: elevated
                      ? context.accent.withValues(alpha: 0.18)
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
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: SizedBox.square(
                          dimension: 40,
                          child: Frosted(
                            radius: 14,
                            blur: 16,
                            color: context.accent.withValues(alpha: 0.14),
                            child: Center(
                              child: Icon(
                                semanticLabel: 'Back',
                                CupertinoIcons.chevron_left,
                                size: 18,
                                color: context.accent,
                              ),
                            ),
                          ),
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
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<DashTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;
    final double bottom = MediaQuery.paddingOf(context).bottom;

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottom > 0 ? bottom : 12),
        child: SizedBox(
          height: kDashTabBarHeight,
          child: Frosted(
            radius: 28,
            padding: const EdgeInsets.all(6),
            color: DashColors.card(isDark).withValues(alpha: 0.82),
            borderColor: DashColors.border(isDark),
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
                                    context.accent.withValues(alpha: 0.24),
                                    context.accent2.withValues(alpha: 0.2),
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
                                  ? context.accent
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
