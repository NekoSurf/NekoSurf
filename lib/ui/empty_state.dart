import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/ui/colors.dart';

/// What a page shows when there's nothing on it yet, or what's on it
/// couldn't load: a picture, a heading, a line saying what to do, and a
/// button to do it, the same on every page.
class DashEmptyState extends StatelessWidget {
  const DashEmptyState({
    super.key,
    this.icon,
    this.art,
    required this.title,
    required this.message,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  }) : assert(icon != null || art != null);

  /// In a tinted circle, when there's no [art].
  final IconData? icon;

  /// A picture of its own, like the app's cat on an empty Bookmarks tab.
  final Widget? art;
  final String title;
  final String message;

  /// The button under it, when there's something to do.
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  /// A second, quieter way on, like opening the page in the browser.
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final String? actionLabel = this.actionLabel;
    final IconData? actionIcon = this.actionIcon;
    final VoidCallback? onAction = this.onAction;
    final String? secondaryLabel = this.secondaryLabel;
    final VoidCallback? onSecondary = this.onSecondary;

    // In the middle of the room it's given, where it fills a page.
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            art ?? _IconArt(icon: icon!),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: DashColors.text(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: DashColors.muted(context),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 22),
              CupertinoButton(
                color: context.accent,
                borderRadius: BorderRadius.circular(16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 13,
                ),
                onPressed: onAction,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (actionIcon != null) ...[
                      Icon(actionIcon, size: 18, color: Colors.black),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      actionLabel,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (secondaryLabel != null && onSecondary != null)
              CupertinoButton(
                onPressed: onSecondary,
                child: Text(
                  secondaryLabel,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.accent,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The theme's colours in a ring, round [child]: the picture of an empty
/// page.
class _EmptyArt extends StatelessWidget {
  const _EmptyArt({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            context.accent.withValues(alpha: 0.28),
            context.accent2.withValues(alpha: 0.22),
          ],
        ),
        border: Border.all(color: context.accent.withValues(alpha: 0.3)),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

class _IconArt extends StatelessWidget {
  const _IconArt({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _EmptyArt(child: Icon(icon, size: 44, color: context.accent));
  }
}
