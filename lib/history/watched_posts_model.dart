import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_chan/history/thread_memory.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/sync/cloud_sync.dart';
import 'package:flutter_chan/sync/sync_items.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What's remembered of [thread], as iCloud sync keeps it.
SyncItem threadMemorySyncItem(int thread, ThreadMemory memory) => SyncItem(
  SyncKind.threadMemory,
  '$thread',
  memory.toJson(),
  modifiedAt: memory.changedAt,
);

class WatchedPostsProvider
    with ChangeNotifier, WidgetsBindingObserver
    implements SyncTarget {
  WatchedPostsProvider(this._prefs, this._settings, {CloudSync? sync})
    : _sync = sync ?? CloudSync.instance {
    _load();

    WidgetsBinding.instance.addObserver(this);
    _sync.attach(this);
  }

  final SharedPreferences _prefs;
  final SettingsProvider _settings;
  final CloudSync _sync;

  // Threads changed since they were last stored: they go to iCloud then,
  // not on every scroll.
  final Set<int> _changed = <int>{};
  Timer? _saveDebounceTimer;
  bool _hasPendingSave = false;

  static const String _threadMemoryStorageKey = 'threadMemory';
  static const Duration _saveDebounceDelay = Duration(seconds: 2);

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
    if (_hasPendingSave) {
      _save();
      _hasPendingSave = false;
    }
    _saveDebounceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _sync.detach(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _clearOldWatchedPosts();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _persistNow();
    }
  }

  final Map<int, ThreadMemory> _threadMemory = {};

  void _load() {
    // What older versions kept instead.
    unawaited(_prefs.remove('watchedPosts'));

    for (final (int thread, ThreadMemory memory) in storedMemories(_prefs)) {
      _threadMemory[thread] = memory;
    }

    _clearOldWatchedPosts();
  }

  /// What's remembered of each thread, as it's stored in [prefs].
  static List<(int, ThreadMemory)> storedMemories(SharedPreferences prefs) {
    final String? stored = prefs.getString(_threadMemoryStorageKey);
    if (stored == null) {
      return const [];
    }
    try {
      final Map<String, dynamic> threads =
          json.decode(stored) as Map<String, dynamic>;
      return <(int, ThreadMemory)>[
        for (final MapEntry<String, dynamic> entry in threads.entries)
          (
            int.parse(entry.key),
            ThreadMemory.fromJson(entry.value as Map<String, dynamic>),
          ),
      ];
    } catch (e) {
      debugPrint('Error parsing thread memory: $e');
      return const [];
    }
  }

  /// [thread]'s memory, to be changed now.
  ThreadMemory _memoryOf(int thread) {
    _changed.add(thread);
    return _threadMemory.putIfAbsent(thread, ThreadMemory.new)
      ..changedAt = DateTime.now();
  }

  /// Takes note of the [posts] in [thread], oldest first. The first time,
  /// all but the opening post are unseen till they've been on screen, but
  /// none is new; after that, those posted since are unseen and new.
  void noteThreadPosts(int thread, List<int> posts) {
    if (posts.isEmpty) {
      return;
    }
    final ThreadMemory memory = _memoryOf(thread);
    final int? newest = memory.newestPost;
    if (newest == null) {
      memory.unseen.addAll(posts.skip(1));
      memory.firstNewestPost = posts.reduce(max);
    } else {
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

  /// The posts in [thread] that haven't been on screen yet: unread ones
  /// that were there when it was first read, and new ones since.
  Set<int> unseenPosts(int thread) =>
      Set<int>.unmodifiable(_threadMemory[thread]?.unseen ?? const <int>{});

  /// The [unseenPosts] posted since [thread] was first read.
  Set<int> newPosts(int thread) {
    final ThreadMemory? memory = _threadMemory[thread];
    if (memory == null) {
      return const <int>{};
    }
    final int? first = memory.firstNewestPost;
    return Set<int>.unmodifiable(
      first == null ? memory.unseen : memory.unseen.where((p) => p > first),
    );
  }

  void markPostsSeen(int thread, Iterable<int> posts) {
    final ThreadMemory? memory = _threadMemory[thread];
    if (memory == null || !memory.unseen.any(posts.contains)) {
      return;
    }
    _memoryOf(thread).unseen.removeAll(posts);
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

  /// Goes up each time a post or ID is hidden or shown again, in any thread.
  int get hidingChanges => _hidingChanges;
  int _hidingChanges = 0;

  /// Hides [post] in [thread], or shows it again.
  void setPostHidden(int thread, int post, {required bool hidden}) {
    final Set<int> posts = _memoryOf(thread).hiddenPosts;
    _changeHiding(hidden ? posts.add(post) : posts.remove(post));
  }

  /// Hides the posts by [id] in [thread], or shows them again.
  void setIdHidden(int thread, String id, {required bool hidden}) {
    final Set<String> ids = _memoryOf(thread).hiddenIds;
    _changeHiding(hidden ? ids.add(id) : ids.remove(id));
  }

  void _changeHiding(bool changed) {
    if (changed) {
      _hidingChanges++;
      _schedulePersist();
      notifyListeners();
    }
  }

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

  Future<void> _save() {
    if (_changed.isNotEmpty) {
      _sync.putAll(<SyncItem>[
        for (final int thread in _changed)
          if (_threadMemory[thread] case final ThreadMemory memory)
            threadMemorySyncItem(thread, memory),
      ]);
      _changed.clear();
    }
    return _store();
  }

  Future<void> _store() => _prefs.setString(
    _threadMemoryStorageKey,
    json.encode(<String, dynamic>{
      for (final MapEntry<int, ThreadMemory> entry in _threadMemory.entries)
        '${entry.key}': entry.value.toJson(),
    }),
  );

  Future<void> clearAllWatchedPosts() async {
    _sync.removeAll(SyncKind.threadMemory, [
      for (final int thread in _threadMemory.keys) '$thread',
    ]);
    _threadMemory.clear();
    _changed.clear();
    await _save();
    notifyListeners();
  }

  Future<void> _clearOldWatchedPosts() async {
    final DateTime cutoffDate = DateTime.now().subtract(
      Duration(days: _settings.watchedPostsRetentionDays.value),
    );

    final List<int> old = <int>[
      for (final MapEntry<int, ThreadMemory> entry in _threadMemory.entries)
        if (entry.value.lastRead.isBefore(cutoffDate)) entry.key,
    ];
    if (old.isNotEmpty) {
      old.forEach(_threadMemory.remove);
      _changed.removeAll(old);
      _sync.removeAll(SyncKind.threadMemory, [
        for (final int thread in old) '$thread',
      ]);
      notifyListeners();
      await _save();
    }
  }

  @override
  Set<SyncKind> get syncKinds => const <SyncKind>{SyncKind.threadMemory};

  /// What's remembered of a thread on another device replaces what's here,
  /// if it changed there since, unless it's older than this device keeps.
  @override
  Future<void> applySync(List<SyncChange> changes) async {
    final DateTime cutoff = DateTime.now().subtract(
      Duration(days: _settings.watchedPostsRetentionDays.value),
    );
    bool changed = false;
    for (final SyncChange change in changes) {
      final int? thread = int.tryParse(change.key ?? '');
      if (thread == null) {
        continue;
      }
      if (change.deleted) {
        changed |= _threadMemory.remove(thread) != null;
        _changed.remove(thread);
        continue;
      }
      final ThreadMemory remote;
      try {
        remote = ThreadMemory.fromJson(change.data.cast<String, dynamic>());
      } catch (_) {
        continue;
      }
      final ThreadMemory? here = _threadMemory[thread];
      if (remote.lastRead.isBefore(cutoff) ||
          (here != null && !remote.changedAt.isAfter(here.changedAt))) {
        continue;
      }
      _threadMemory[thread] = remote;
      _changed.remove(thread);
      changed = true;
    }
    if (changed) {
      // What's hidden may have changed too.
      _hidingChanges++;
      notifyListeners();
      await _store();
    }
  }
}
