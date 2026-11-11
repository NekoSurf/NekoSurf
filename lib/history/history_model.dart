import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/chan/thread_status.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/sync/cloud_sync.dart';
import 'package:flutter_chan/sync/sync_items.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryThread {
  HistoryThread({
    required this.board,
    required this.no,
    required this.title,
    required this.visitedAt,
    this.imageUrl,
    this.com,
  });

  factory HistoryThread.fromJson(Map<String, dynamic> json) {
    return HistoryThread(
      board: json['board'] as String,
      no: json['no'] as int,
      title: json['title'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      com: json['com'] as String?,
      visitedAt: DateTime.fromMillisecondsSinceEpoch(json['at'] as int),
    );
  }

  final String board;
  final int no;
  final String title;
  final String? imageUrl;
  final String? com;
  final DateTime visitedAt;

  String get key => '$board/$no';

  /// What's known of the thread's opening post.
  Post toPost() => Post.remembered(
    board: board,
    no: no,
    sub: title.isEmpty ? null : title,
    com: com,
    thumbnailName: imageUrl,
  );

  Map<String, dynamic> toJson() => {
    'board': board,
    'no': no,
    'title': title,
    'imageUrl': imageUrl,
    'com': com,
    'at': visitedAt.millisecondsSinceEpoch,
  };
}

/// [thread], as iCloud sync keeps it.
SyncItem historySyncItem(HistoryThread thread) => SyncItem(
  SyncKind.history,
  thread.key,
  thread.toJson(),
  modifiedAt: thread.visitedAt,
);

class HistoryProvider with ChangeNotifier implements SyncTarget {
  HistoryProvider(this._prefs, this._settings, {CloudSync? sync})
    : _sync = sync ?? CloudSync.instance {
    _threads = _decode(
      _prefs.getStringList(storageKey),
      (m) => HistoryThread.fromJson(m),
    );
    // What older versions kept too, and nothing ever showed.
    unawaited(_prefs.remove('historyBoards'));
    _sync.attach(this);
  }

  /// Where the visited threads are kept in SharedPreferences.
  static const String storageKey = 'historyThreads';
  static const int _maxThreads = 100;

  final SharedPreferences _prefs;
  final SettingsProvider _settings;
  final CloudSync _sync;
  List<HistoryThread> _threads = [];
  final Set<String> _archived = {};
  final Map<String, int> _replies = {};

  List<HistoryThread> get threads => List.unmodifiable(_threads);

  bool isArchived(HistoryThread t) => _archived.contains(t.key);

  /// Reply count from the last status check, if known.
  int? replies(HistoryThread t) => _replies[t.key];

  Future<void> _saveThreads() => _prefs.setStringList(
    storageKey,
    _threads.map((t) => json.encode(t.toJson())).toList(),
  );

  List<T> _decode<T>(
    List<String>? raw,
    T Function(Map<String, dynamic>) parse,
  ) {
    final result = <T>[];
    for (final item in raw ?? const <String>[]) {
      try {
        result.add(parse(json.decode(item) as Map<String, dynamic>));
      } catch (_) {
        // Skip corrupt entries.
      }
    }
    return result;
  }

  /// Puts the thread [op] opens at the top, if history is on.
  Future<void> recordThread(Post op) async {
    if (!_settings.trackHistory.value) {
      return;
    }
    final HistoryThread visited = HistoryThread(
      board: op.board,
      no: op.no,
      title: op.title,
      imageUrl: op.thumbnailName,
      com: op.com,
      visitedAt: DateTime.now(),
    );
    _threads
      ..removeWhere((t) => t.key == visited.key)
      ..insert(0, visited);
    _sync.put(historySyncItem(visited));
    _trim();

    notifyListeners();
    await _saveThreads();
  }

  static const Duration _checkInterval = Duration(minutes: 5);
  DateTime? _lastCheck;

  /// Drops threads that 4chan no longer has and remembers which are archived.
  /// Runs at most every few minutes unless [force]d (pull to refresh).
  Future<void> checkThreads({bool force = false}) async {
    final DateTime now = DateTime.now();
    if (!force &&
        _lastCheck != null &&
        now.difference(_lastCheck!) < _checkInterval) {
      return;
    }
    _lastCheck = now;

    final threads = List.of(_threads);
    final statuses = await Future.wait(
      threads.map((t) => checkThread(t.board, t.no, force: force)),
    );

    final deleted = <String>{};
    for (int i = 0; i < threads.length; i++) {
      final String key = threads[i].key;
      final int? replies = statuses[i]?.replies;
      if (replies != null) {
        _replies[key] = replies;
      }
      switch (statuses[i]?.status) {
        case ThreadStatus.deleted:
          deleted.add(key);
          _archived.remove(key);
        case ThreadStatus.archived:
          _archived.add(key);
        case ThreadStatus.online:
          _archived.remove(key);
        case null:
          break;
      }
    }

    if (deleted.isNotEmpty) {
      _threads.removeWhere((t) => deleted.contains(t.key));
      _sync.removeAll(SyncKind.history, deleted);
    }
    notifyListeners();

    if (deleted.isNotEmpty) {
      await _saveThreads();
    }
  }

  /// Turns history on or off, which forgets what's in it.
  Future<void> setTracking(bool tracking) async {
    await _settings.trackHistory.set(tracking);
    if (!tracking) {
      await clear();
    }
  }

  Future<void> removeThread(HistoryThread thread) async {
    _threads.removeWhere((t) => t.key == thread.key);
    _sync.remove(SyncKind.history, thread.key);
    notifyListeners();
    await _saveThreads();
  }

  Future<void> clear() async {
    _sync.removeAll(SyncKind.history, [for (final t in _threads) t.key]);
    _threads = [];
    notifyListeners();
    await _prefs.remove(storageKey);
  }

  /// Keeps the newest [_maxThreads]; what goes, goes everywhere.
  void _trim() {
    if (_threads.length > _maxThreads) {
      _sync.removeAll(SyncKind.history, [
        for (final t in _threads.skip(_maxThreads)) t.key,
      ]);
      _threads = _threads.sublist(0, _maxThreads);
    }
  }

  @override
  Set<SyncKind> get syncKinds => const <SyncKind>{SyncKind.history};

  /// A thread visited on another device takes its place by when it was
  /// visited, unless it was visited here since.
  @override
  Future<void> applySync(List<SyncChange> changes) async {
    for (final SyncChange change in changes) {
      if (change.deleted) {
        _threads.removeWhere((HistoryThread t) => change.isFor(t.key));
        continue;
      }
      if (!_settings.trackHistory.value) {
        continue;
      }
      final HistoryThread visited;
      try {
        visited = HistoryThread.fromJson(change.data.cast<String, dynamic>());
      } catch (_) {
        continue;
      }
      final HistoryThread? here = _threads
          .where((t) => t.key == visited.key)
          .firstOrNull;
      if (here != null && !visited.visitedAt.isAfter(here.visitedAt)) {
        continue;
      }
      _threads
        ..removeWhere((t) => t.key == visited.key)
        ..add(visited);
    }
    _threads.sort((a, b) => b.visitedAt.compareTo(a.visitedAt));
    _trim();
    notifyListeners();
    await _saveThreads();
  }

  @override
  void dispose() {
    _sync.detach(this);
    super.dispose();
  }
}
