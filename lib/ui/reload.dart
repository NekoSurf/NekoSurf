import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/chan/load_errors.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/empty_state.dart';

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

  /// Says what went wrong with [error]: 4chan limiting requests, not
  /// having the page, or failing itself; otherwise (no connection, most
  /// likely) the default.
  factory ReloadWidget.forError(
    Object? error, {
    required VoidCallback onReload,
  }) {
    final (IconData icon, String title, String message) = switch (error) {
      ApiException(isRateLimited: true) => (
        CupertinoIcons.hourglass,
        'Too many requests',
        '4chan is limiting requests for now. Wait a moment, then try again.',
      ),
      ApiException(statusCode: 404) || ThreadNotFound() => (
        CupertinoIcons.question_circle,
        'Not found',
        "4chan doesn't have this page (anymore).",
      ),
      ApiException(statusCode: >= 500) => (
        CupertinoIcons.exclamationmark_triangle,
        '4chan is having trouble',
        'Its servers answered with an error. Try again in a bit.',
      ),
      _ => (
        CupertinoIcons.wifi_exclamationmark,
        'Loading failed',
        'Check your connection and try again.',
      ),
    };
    return ReloadWidget(
      onReload: onReload,
      icon: icon,
      title: title,
      message: message,
    );
  }

  final VoidCallback onReload;
  final IconData icon;
  final String title;
  final String message;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DashColors.page(context),
      child: Center(
        child: SingleChildScrollView(
          child: DashEmptyState(
            icon: icon,
            title: title,
            message: message,
            actionLabel: 'Try again',
            actionIcon: CupertinoIcons.arrow_counterclockwise,
            onAction: onReload,
            secondaryLabel: secondaryLabel,
            onSecondary: onSecondary,
          ),
        ),
      ),
    );
  }
}
