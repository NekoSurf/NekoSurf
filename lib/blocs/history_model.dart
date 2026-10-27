import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_chan/API/archived.dart';
import 'package:flutter_chan/enums/enums.dart';
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

  Map<String, dynamic> toJson() => {
    'board': board,
    'no': no,
    'title': title,
    'imageUrl': imageUrl,
    'com': com,
    'at': visitedAt.millisecondsSinceEpoch,
  };
}

class HistoryBoard {
  HistoryBoard({
    required this.board,
    required this.title,
    required this.visitedAt,
  });

  factory HistoryBoard.fromJson(Map<String, dynamic> json) {
    return HistoryBoard(
      board: json['board'] as String,
      title: json['title'] as String? ?? '',
      visitedAt: DateTime.fromMillisecondsSinceEpoch(json['at'] as int),
    );
  }

  final String board;
  final String title;
  final DateTime visitedAt;

  Map<String, dynamic> toJson() => {
    'board': board,
    'title': title,
    'at': visitedAt.millisecondsSinceEpoch,
  };
}

class HistoryProvider with ChangeNotifier {
  HistoryProvider() {
    _ready = _load();
  }

  static const String _threadsKey = 'historyThreads';
  static const String _boardsKey = 'historyBoards';
  static const int maxThreads = 12;
  static const int maxBoards = 8;

  late final Future<void> _ready;
  List<HistoryThread> _threads = [];
  List<HistoryBoard> _boards = [];
  final Set<String> _archived = {};

  List<HistoryThread> get threads => List.unmodifiable(_threads);
  List<HistoryBoard> get boards => List.unmodifiable(_boards);
  bool get isEmpty => _threads.isEmpty && _boards.isEmpty;

  bool isArchived(HistoryThread t) => _archived.contains(_key(t));

  String _key(HistoryThread t) => '${t.board}/${t.no}';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    _threads = _decode(
      prefs.getStringList(_threadsKey),
      (m) => HistoryThread.fromJson(m),
    );
    _boards = _decode(
      prefs.getStringList(_boardsKey),
      (m) => HistoryBoard.fromJson(m),
    );

    notifyListeners();
  }

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

  Future<void> recordThread({
    required String board,
    required int no,
    required String title,
    String? imageUrl,
    String? com,
  }) async {
    _threads
      ..removeWhere((t) => t.board == board && t.no == no)
      ..insert(
        0,
        HistoryThread(
          board: board,
          no: no,
          title: title,
          imageUrl: imageUrl,
          com: com,
          visitedAt: DateTime.now(),
        ),
      );
    if (_threads.length > maxThreads) {
      _threads = _threads.sublist(0, maxThreads);
    }

    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _threadsKey,
      _threads.map((t) => json.encode(t.toJson())).toList(),
    );
  }

  Future<void> recordBoard({
    required String board,
    required String title,
  }) async {
    _boards
      ..removeWhere((b) => b.board == board)
      ..insert(
        0,
        HistoryBoard(board: board, title: title, visitedAt: DateTime.now()),
      );
    if (_boards.length > maxBoards) {
      _boards = _boards.sublist(0, maxBoards);
    }

    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _boardsKey,
      _boards.map((b) => json.encode(b.toJson())).toList(),
    );
  }

  /// Drops threads that 4chan no longer has and remembers which are archived.
  Future<void> checkThreads() async {
    await _ready;
    final threads = List.of(_threads);
    final statuses = await Future.wait(
      threads.map((t) => fetchThreadStatus(t.board, t.no)),
    );

    final deleted = <String>{};
    for (int i = 0; i < threads.length; i++) {
      final key = _key(threads[i]);
      switch (statuses[i]) {
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
      _threads.removeWhere((t) => deleted.contains(_key(t)));
    }
    notifyListeners();

    if (deleted.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _threadsKey,
        _threads.map((t) => json.encode(t.toJson())).toList(),
      );
    }
  }

  Future<void> removeThread(HistoryThread thread) async {
    _threads.removeWhere((t) => t.board == thread.board && t.no == thread.no);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _threadsKey,
      _threads.map((t) => json.encode(t.toJson())).toList(),
    );
  }

  Future<void> clear() async {
    _threads = [];
    _boards = [];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_threadsKey);
    await prefs.remove(_boardsKey);
  }
}
