import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/constants.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:provider/provider.dart';

/// Shown in place of content that failed to load, with a retry button and
/// optionally a second way out, like opening the page in the browser.
class ReloadWidget extends StatelessWidget {
  const ReloadWidget({
    super.key,
    required this.onReload,
    this.icon = CupertinoIcons.wifi_exclamationmark,
    this.title = 'Loading failed',
    this.message = 'Check your connection and try again.',
    this.secondaryLabel,
    this.onSecondary,
  });

  final Function() onReload;
  final IconData icon;
  final String title;
  final String message;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Provider.of<ThemeChanger>(context).isDark;

    return ColoredBox(
      color: AppColors.pageBackground(isDark),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: DashColors.accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 28, color: DashColors.accent),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: DashColors.text(isDark),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: DashColors.muted(isDark),
                ),
              ),
              const SizedBox(height: 20),
              CupertinoButton(
                color: DashColors.accent,
                borderRadius: BorderRadius.circular(999),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 10,
                ),
                onPressed: onReload,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.arrow_counterclockwise,
                      size: 18,
                      color: Colors.black,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Try again',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              if (secondaryLabel != null && onSecondary != null)
                CupertinoButton(
                  onPressed: onSecondary,
                  child: Text(
                    secondaryLabel!,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: DashColors.accent,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
