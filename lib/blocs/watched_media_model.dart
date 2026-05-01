import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/watched_media.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WatchedPostsProvider with ChangeNotifier, WidgetsBindingObserver {
  WatchedPostsProvider() {
    loadWatchedPosts();

    WidgetsBinding.instance.addObserver(this);

    _startCleanupTimer();
  }

  Timer? _cleanupTimer;

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      clearOldWatchedPosts();
    });
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      clearOldWatchedPosts();
    }
  }

  final List<WatchedPosts> _watchedPosts = [];
  List<WatchedPosts> get watchedPosts => List.unmodifiable(_watchedPosts);

  Future<void> loadWatchedPosts() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String>? watchedPostsList = prefs.getStringList('watchedPosts');

    if (watchedPostsList != null) {
      _watchedPosts.clear();

      for (final String watchedPostsString in watchedPostsList) {
        try {
          final Map<String, dynamic> watchedPostsMap =
              json.decode(watchedPostsString) as Map<String, dynamic>;
          _watchedPosts.add(WatchedPosts.fromJson(watchedPostsMap));
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
    final WatchedPosts newWatchedPost = WatchedPosts(
      postIndex: postIndex,
      thread: thread,
      watchedAt: DateTime.now(),
    );

    final existingMediaIndex = _watchedPosts.indexWhere(
      (media) => media.postIndex == postIndex && media.thread == thread,
    );

    if (existingMediaIndex != -1) {
      _watchedPosts[existingMediaIndex] = newWatchedPost;
    } else {
      _watchedPosts.add(newWatchedPost);
    }

    await _saveWatchedPosts();
    notifyListeners();
  }

  Future<void> removeFromWatched(int postIndex, int thread) async {
    _watchedPosts.removeWhere(
      (media) => media.postIndex == postIndex && media.thread == thread,
    );
    await _saveWatchedPosts();
    notifyListeners();
  }

  Future<void> _saveWatchedPosts() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> watchedPostsStrings = _watchedPosts
        .map((media) => json.encode(media.toJson()))
        .toList();
    await prefs.setStringList('watchedPosts', watchedPostsStrings);
  }

  Future<void> clearAllWatchedPosts() async {
    _watchedPosts.clear();
    await _saveWatchedPosts();
    notifyListeners();
  }

  Future<void> clearOldWatchedPosts() async {
    final settings = await SharedPreferences.getInstance();
    final int retentionDays = settings.getInt('watchedPostsRetentionDays') ?? 7;

    final DateTime cutoffDate = DateTime.now().subtract(
      Duration(days: retentionDays),
    );

    _watchedPosts.removeWhere((media) => media.watchedAt.isBefore(cutoffDate));

    await _saveWatchedPosts();
    notifyListeners();
  }

  WatchedPosts? getLatestWatchedPosts(int thread) {
    final threadMedia = _watchedPosts
        .where((media) => media.thread == thread)
        .toList();

    if (threadMedia.isEmpty) {
      return null;
    }

    return threadMedia.reduce(
      (a, b) => a.watchedAt.isAfter(b.watchedAt) ? a : b,
    );
  }
}
