import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/thread_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WatchedPostsProvider with ChangeNotifier, WidgetsBindingObserver {
  WatchedPostsProvider(this._prefs) {
    _load();

    WidgetsBinding.instance.addObserver(this);

    _startCleanupTimer();
  }

  final SharedPreferences _prefs;
  Timer? _cleanupTimer;
  Timer? _saveDebounceTimer;
  bool _hasPendingSave = false;

  static const String _threadMemoryStorageKey = 'threadMemory';
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
    await _save();
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    if (_hasPendingSave) {
      _save();
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

  // Pages ask for this when they build, so changing it doesn't notify anyone.
  final Map<int, ThreadMemory> _threadMemory = {};

  void _load() {
    // What older versions kept instead.
    unawaited(_prefs.remove('watchedPosts'));

    final String? stored = _prefs.getString(_threadMemoryStorageKey);
    if (stored != null) {
      try {
        final Map<String, dynamic> threads =
            json.decode(stored) as Map<String, dynamic>;
        threads.forEach((String thread, dynamic value) {
          _threadMemory[int.parse(thread)] = ThreadMemory.fromJson(
            value as Map<String, dynamic>,
          );
        });
      } catch (e) {
        debugPrint('Error parsing thread memory: $e');
      }
    }

    clearOldWatchedPosts();
  }

  ThreadMemory _memoryOf(int thread) =>
      _threadMemory.putIfAbsent(thread, ThreadMemory.new);

  /// Takes note of the [posts] in [thread], oldest first: those posted since it
  /// was last open are unseen.
  void noteThreadPosts(int thread, List<int> posts) {
    if (posts.isEmpty) {
      return;
    }
    final ThreadMemory memory = _memoryOf(thread);
    final int? newest = memory.newestPost;
    if (newest != null) {
      memory.unseen.addAll(posts.where((int post) => post > newest));
    }
    // Deleted posts can't be seen any more.
    memory.unseen.retainAll(posts);
    memory.newestPost = posts.reduce(max);
    memory.knownReplies = posts.length - 1;
    memory.lastRead = DateTime.now();
    _schedulePersist();
    notifyListeners();
  }

  /// The posts in [thread] that were posted since it was first read and haven't
  /// been on screen yet.
  Set<int> unseenPosts(int thread) =>
      Set<int>.unmodifiable(_threadMemory[thread]?.unseen ?? const <int>{});

  void markPostsSeen(int thread, Iterable<int> posts) {
    _threadMemory[thread]?.unseen.removeAll(posts);
    _schedulePersist();
    notifyListeners();
  }

  /// Remembers the row at the top of the screen in [thread], and how far down
  /// the screen it starts.
  void rememberPlace(
    int thread, {
    required int post,
    required String path,
    required double alignment,
  }) {
    _memoryOf(thread)
      ..topPost = post
      ..topPath = path
      ..topAlignment = alignment
      ..lastRead = DateTime.now();
    _schedulePersist();
  }

  /// Remembers what's folded in [thread], and where posts were moved to.
  void rememberFolds(
    int thread, {
    required Set<String> folded,
    required Map<int, int> primaryParents,
  }) {
    _memoryOf(thread)
      ..folded.clear()
      ..folded.addAll(folded)
      ..primaryParents.clear()
      ..primaryParents.addAll(primaryParents);
    _schedulePersist();
  }

  /// What's remembered about [thread], if it's been open.
  ThreadMemory? threadMemory(int thread) => _threadMemory[thread];

  /// The replies in [thread] not seen yet, given its current reply count: those
  /// known to be unseen, and any posted since it was last loaded. Null if it
  /// hasn't been open (or that's been forgotten), so unread threads don't show a
  /// misleading count.
  int? newReplies(int thread, int replies) {
    final ThreadMemory? memory = _threadMemory[thread];
    final int? knownReplies = memory?.knownReplies;
    if (memory == null || knownReplies == null) {
      return null;
    }
    return memory.unseen.length + max(0, replies - knownReplies);
  }

  Future<void> _save() => _prefs.setString(
    _threadMemoryStorageKey,
    json.encode(<String, dynamic>{
      for (final MapEntry<int, ThreadMemory> entry in _threadMemory.entries)
        '${entry.key}': entry.value.toJson(),
    }),
  );

  Future<void> clearAllWatchedPosts() async {
    _threadMemory.clear();
    await _save();
    notifyListeners();
  }

  Future<void> clearOldWatchedPosts() async {
    final int retentionDays = _prefs.getInt('watchedPostsRetentionDays') ?? 7;

    final DateTime cutoffDate = DateTime.now().subtract(
      Duration(days: retentionDays),
    );

    _threadMemory.removeWhere(
      (_, ThreadMemory memory) => memory.lastRead.isBefore(cutoffDate),
    );

    await _save();
    notifyListeners();
  }
}
