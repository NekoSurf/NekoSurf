import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/hover.dart';
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
    final Widget card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: DashColors.card(context),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: DashColors.border(context)),
      ),
      child: child,
    );
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: onTap == null ? card : HoverHighlight(radius: radius, child: card),
    );
  }
}

class DashSectionHeader extends StatelessWidget {
  const DashSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.top = 28,
  });

  final String title;

  /// On the right, in line with the title: a link or a count.
  final Widget? trailing;

  /// Room above it.
  final double top;

  @override
  Widget build(BuildContext context) {
    final Widget? trailing = this.trailing;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, top, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: DashColors.text(context),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A count beside a section's title, like "5 files".
class DashSectionCount extends StatelessWidget {
  const DashSectionCount(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 13, color: DashColors.muted(context)),
    );
  }
}

/// A link beside a section's title, like "History".
class DashSectionLink extends StatelessWidget {
  const DashSectionLink(this.text, {super.key, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: context.accent,
          ),
        ),
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
    this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String> onChanged;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: CupertinoSearchTextField(
        controller: controller,
        focusNode: focusNode,
        placeholder: placeholder,
        backgroundColor: DashColors.card(context),
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
