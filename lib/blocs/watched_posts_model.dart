import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/watched_posts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WatchedPostsProvider with ChangeNotifier, WidgetsBindingObserver {
  WatchedPostsProvider() {
    loadWatchedPosts();

    WidgetsBinding.instance.addObserver(this);

    _startCleanupTimer();
  }

  Timer? _cleanupTimer;
  Timer? _saveDebounceTimer;
  bool _hasPendingSave = false;

  static const String _watchedPostsStorageKey = 'watchedPosts';
  static const Duration _saveDebounceDelay = Duration(seconds: 2);

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      clearOldWatchedPosts();
    });
  }

  void _schedulePersist() {
    _hasPendingSave = true;
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(_saveDebounceDelay, () {
      _persistNow();
    });
  }

  Future<void> _persistNow() async {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;

    if (!_hasPendingSave) {
      return;
    }

    _hasPendingSave = false;
    await _saveWatchedPosts();
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    if (_hasPendingSave) {
      _saveWatchedPosts();
      _hasPendingSave = false;
    }
    _saveDebounceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      clearOldWatchedPosts();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _persistNow();
    }
  }

  final Map<int, WatchedPosts> _watchedPostsByThread = {};
  List<WatchedPosts> get watchedPosts =>
      List.unmodifiable(_watchedPostsByThread.values);

  Future<void> loadWatchedPosts() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String>? watchedPostsList = prefs.getStringList(
      _watchedPostsStorageKey,
    );

    if (watchedPostsList != null) {
      _watchedPostsByThread.clear();

      for (final String watchedPostsString in watchedPostsList) {
        try {
          final Map<String, dynamic> watchedPostsMap =
              json.decode(watchedPostsString) as Map<String, dynamic>;
          final parsed = WatchedPosts.fromJson(watchedPostsMap);
          final existing = _watchedPostsByThread[parsed.thread];
          if (existing == null ||
              parsed.watchedAt.isAfter(existing.watchedAt)) {
            _watchedPostsByThread[parsed.thread] = parsed;
          }
        } catch (e) {
          debugPrint('Error parsing watched posts entry: $e');
        }
      }
      notifyListeners();
    }

    clearOldWatchedPosts();
  }

  Future<void> markAsWatched({
    required int postIndex,
    required int thread,
  }) async {
    final existing = _watchedPostsByThread[thread];
    if (existing != null &&
        existing.postIndex == postIndex &&
        DateTime.now().difference(existing.watchedAt) <
            const Duration(seconds: 10)) {
      return;
    }

    final WatchedPosts latestForThread = WatchedPosts(
      postIndex: postIndex,
      thread: thread,
      watchedAt: DateTime.now(),
    );

    _watchedPostsByThread[thread] = latestForThread;
    _schedulePersist();
    notifyListeners();
  }

  Future<void> removeFromWatched(int postIndex, int thread) async {
    final existing = _watchedPostsByThread[thread];
    if (existing == null || existing.postIndex != postIndex) {
      return;
    }

    _watchedPostsByThread.remove(thread);
    await _saveWatchedPosts();
    notifyListeners();
  }

  Future<void> _saveWatchedPosts() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> watchedPostsStrings = _watchedPostsByThread.values
        .map((media) => json.encode(media.toJson()))
        .toList();
    await prefs.setStringList(_watchedPostsStorageKey, watchedPostsStrings);
  }

  Future<void> clearAllWatchedPosts() async {
    _watchedPostsByThread.clear();
    await _saveWatchedPosts();
    notifyListeners();
  }

  Future<void> clearOldWatchedPosts() async {
    final settings = await SharedPreferences.getInstance();
    final int retentionDays = settings.getInt('watchedPostsRetentionDays') ?? 7;

    final DateTime cutoffDate = DateTime.now().subtract(
      Duration(days: retentionDays),
    );

    _watchedPostsByThread.removeWhere(
      (_, media) => media.watchedAt.isBefore(cutoffDate),
    );

    await _saveWatchedPosts();
    notifyListeners();
  }

  WatchedPosts? getLatestWatchedPosts(int thread) {
    return _watchedPostsByThread[thread];
  }
}
