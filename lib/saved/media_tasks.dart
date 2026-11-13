import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_chan/saved/downloads.dart';

/// Something done to each of several files, each on its own, so several can be
/// under way: which are, how far along each is, and a moment's check mark for
/// each that's done, whatever's on screen by then.
class MediaTasks extends ChangeNotifier {
  static const Duration _doneShown = Duration(milliseconds: 1200);

  final Map<String, ValueNotifier<double?>> _running =
      <String, ValueNotifier<double?>>{};
  final Map<String, Timer> _done = <String, Timer>{};
  bool _disposed = false;

  bool isRunning(String key) => _running.containsKey(key);

  /// Nothing is running.
  bool get isIdle => _running.isEmpty;

  /// How far along [key] is, while it's running.
  ValueListenable<double?>? progressOf(String key) => _running[key];

  bool isDone(String key) => _done.containsKey(key);

  /// Runs [task] for [key] unless it's running already. A failure is [task]'s
  /// caller's to deal with; only without one [key] counts as done.
  Future<void> run(String key, Future<void> Function(SaveProgress) task) async {
    if (isRunning(key)) {
      return;
    }
    // Not disposed: a ring may still be listening until it rebuilds.
    final ValueNotifier<double?> progress = ValueNotifier<double?>(null);
    _running[key] = progress;
    _changed();
    try {
      await task((double? value) => progress.value = value);
      _showDone(key);
    } finally {
      _running.remove(key);
      _changed();
    }
  }

  void _showDone(String key) {
    _done[key]?.cancel();
    _done[key] = Timer(_doneShown, () {
      _done.remove(key);
      _changed();
    });
    _changed();
  }

  void _changed() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final Timer timer in _done.values) {
      timer.cancel();
    }
    super.dispose();
  }
}
