import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/watched_posts.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final watchedPostsProvider =
    NotifierProvider<WatchedPostsNotifier, Map<int, WatchedPosts>>(
      WatchedPostsNotifier.new,
    );

class WatchedPostsNotifier extends Notifier<Map<int, WatchedPosts>>
    with WidgetsBindingObserver {
  Timer? _cleanupTimer;
  Timer? _saveDebounceTimer;
  bool _hasPendingSave = false;

  static const String _watchedPostsStorageKey = 'watchedPosts';
  static const Duration _saveDebounceDelay = Duration(seconds: 2);

  @override
  Map<int, WatchedPosts> build() {
    WidgetsBinding.instance.addObserver(this);
    _startCleanupTimer();
    _loadWatchedPosts();

    ref.onDispose(() {
      _cleanupTimer?.cancel();
      if (_hasPendingSave) {
        _saveWatchedPostsSync();
        _hasPendingSave = false;
      }
      _saveDebounceTimer?.cancel();
      WidgetsBinding.instance.removeObserver(this);
    });

    return {};
  }

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 10), (_) {
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
    if (!_hasPendingSave) return;
    _hasPendingSave = false;
    await _saveWatchedPosts();
  }

  // Fire-and-forget variant used from dispose (async not allowed there).
  void _saveWatchedPostsSync() {
    _saveWatchedPosts();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    if (appState == AppLifecycleState.resumed) {
      clearOldWatchedPosts();
    } else if (appState == AppLifecycleState.paused ||
        appState == AppLifecycleState.inactive ||
        appState == AppLifecycleState.detached) {
      _persistNow();
    }
  }

  Future<void> _loadWatchedPosts() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String>? watchedPostsList = prefs.getStringList(
      _watchedPostsStorageKey,
    );

    if (watchedPostsList != null) {
      final Map<int, WatchedPosts> loaded = {};
      for (final String watchedPostsString in watchedPostsList) {
        try {
          final Map<String, dynamic> map =
              json.decode(watchedPostsString) as Map<String, dynamic>;
          final parsed = WatchedPosts.fromJson(map);
          final existing = loaded[parsed.thread];
          if (existing == null || parsed.watchedAt.isAfter(existing.watchedAt)) {
            loaded[parsed.thread] = parsed;
          }
        } catch (e) {
          debugPrint('Error parsing watched posts entry: $e');
        }
      }
      state = Map.unmodifiable(loaded);
    }

    clearOldWatchedPosts();
  }

  Future<void> markAsWatched({
    required int postIndex,
    required int thread,
  }) async {
    final existing = state[thread];
    if (existing != null &&
        existing.postIndex == postIndex &&
        DateTime.now().difference(existing.watchedAt) <
            const Duration(seconds: 10)) {
      return;
    }

    final updated = Map<int, WatchedPosts>.from(state);
    updated[thread] = WatchedPosts(
      postIndex: postIndex,
      thread: thread,
      watchedAt: DateTime.now(),
    );
    state = Map.unmodifiable(updated);
    _schedulePersist();
  }

  Future<void> removeFromWatched(int postIndex, int thread) async {
    final existing = state[thread];
    if (existing == null || existing.postIndex != postIndex) return;

    final updated = Map<int, WatchedPosts>.from(state)..remove(thread);
    state = Map.unmodifiable(updated);
    await _saveWatchedPosts();
  }

  Future<void> _saveWatchedPosts() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> encoded =
        state.values.map((e) => json.encode(e.toJson())).toList();
    await prefs.setStringList(_watchedPostsStorageKey, encoded);
  }

  Future<void> clearAllWatchedPosts() async {
    state = const {};
    await _saveWatchedPosts();
  }

  Future<void> clearOldWatchedPosts() async {
    final int retentionDays =
        ref.read(settingsProvider).watchedPostsRetentionDays;
    final DateTime cutoff = DateTime.now().subtract(
      Duration(days: retentionDays),
    );

    final updated = Map<int, WatchedPosts>.from(state)
      ..removeWhere((_, media) => media.watchedAt.isBefore(cutoff));
    state = Map.unmodifiable(updated);
    await _saveWatchedPosts();
  }

  WatchedPosts? getLatestWatchedPosts(int thread) => state[thread];
}
