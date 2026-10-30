import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.children,
    this.title,
    this.footer,
  });

  final String? title;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final bool isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              child: Text(
                title!.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: DashColors.muted(isDark),
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: DashColors.card(isDark),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: DashColors.border(isDark)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (int i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 68,
                      color: DashColors.border(isDark),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
              child: Text(
                footer!,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: DashColors.muted(isDark),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.showChevron = false,
    this.destructive = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final bool isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: destructive
                          ? DashColors.nsfw
                          : DashColors.text(isDark),
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          color: DashColors.muted(isDark),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (value != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  value!,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DashColors.accent,
                  ),
                ),
              ),
            if (trailing != null)
              Padding(padding: const EdgeInsets.only(left: 8), child: trailing),
            if (showChevron)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  CupertinoIcons.chevron_right,
                  size: 14,
                  color: DashColors.muted(isDark),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CupertinoSwitch(
      value: value,
      activeTrackColor: DashColors.accent,
      onChanged: onChanged,
    );
  }
}
