import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

class DashCard extends StatelessWidget {
  const DashCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.onTap,
    this.radius = 20,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: DashColors.card(isDark),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: DashColors.border(isDark)),
        ),
        child: child,
      ),
    );
  }
}

class DashSectionHeader extends StatelessWidget {
  const DashSectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          color: DashColors.text(isDark),
        ),
      ),
    );
  }
}

class DashPageHeader extends StatelessWidget {
  const DashPageHeader({
    super.key,
    required this.badge,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final Widget badge;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: isDark ? 0.22 : 0.3),
            context.accent2.withValues(alpha: isDark ? 0.12 : 0.18),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(17),
            ),
            alignment: Alignment.center,
            child: badge,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: DashColors.text(isDark),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: DashColors.muted(isDark),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DashSearchField extends StatelessWidget {
  const DashSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.placeholder = 'Search threads',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: CupertinoSearchTextField(
        controller: controller,
        placeholder: placeholder,
        backgroundColor: DashColors.card(isDark),
        onChanged: onChanged,
      ),
    );
  }
}

/// What swiping a row to the left shows: the one thing to do to it, removing it
/// unless told otherwise.
ActionPane swipeActions({
  required String label,
  required IconData icon,
  required VoidCallback onPressed,
  Color color = DashColors.danger,
  Color foregroundColor = Colors.white,
}) {
  return ActionPane(
    extentRatio: 0.3,
    motion: const BehindMotion(),
    children: [
      SlidableAction(
        label: label,
        backgroundColor: color,
        foregroundColor: foregroundColor,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
        icon: icon,
        onPressed: (_) => onPressed(),
      ),
    ],
  );
}
