import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Above the app: where it keeps its preferences, and taking it down and
/// building it again from them, for a restored backup.
class AppRestart extends InheritedWidget {
  const AppRestart({
    super.key,
    required this.prefs,
    required this.restart,
    required super.child,
  });

  /// What the app keeps its preferences in.
  final SharedPreferences prefs;

  /// Takes the app down, so nothing it loaded writes anything afterwards,
  /// runs [work], and builds the app again from what's stored. If [work]
  /// throws, that's shown first. The caller is gone by then.
  final Future<void> Function(Future<void> Function() work) restart;

  static AppRestart of(BuildContext context) => maybeOf(context)!;

  /// Null where the app isn't built by main.dart, as in tests.
  static AppRestart? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppRestart>();

  @override
  bool updateShouldNotify(AppRestart oldWidget) => false;
}
