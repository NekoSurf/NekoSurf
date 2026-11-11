import 'package:flutter/foundation.dart';
import 'package:flutter_chan/sync/cloud_sync.dart';
import 'package:flutter_chan/sync/sync_items.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [board], as iCloud sync keeps it.
SyncItem boardSyncItem(String board) =>
    SyncItem(SyncKind.board, board, {'board': board});

/// Favorite boards, in the order they were added.
class FavoriteProvider with ChangeNotifier implements SyncTarget {
  FavoriteProvider(this._prefs, {CloudSync? sync})
    : _sync = sync ?? CloudSync.instance,
      _boards = _prefs.getStringList(storageKey) ?? <String>[] {
    _sync.attach(this);
  }

  /// Where the favorite boards are kept in SharedPreferences.
  static const String storageKey = 'favoriteBoards';

  final SharedPreferences _prefs;
  final CloudSync _sync;
  final List<String> _boards;

  List<String> get boards => List<String>.unmodifiable(_boards);

  bool contains(String board) => _boards.contains(board);

  Future<void> _add(String board) async {
    if (_boards.contains(board)) {
      return;
    }
    _boards.add(board);
    _sync.put(boardSyncItem(board));
    await _store();
  }

  Future<void> _remove(String board) async {
    _boards.remove(board);
    _sync.remove(SyncKind.board, board);
    await _store();
  }

  Future<void> _store() async {
    notifyListeners();
    await _prefs.setStringList(storageKey, _boards);
  }

  Future<void> toggle(String board) =>
      contains(board) ? _remove(board) : _add(board);

  @override
  Set<SyncKind> get syncKinds => const <SyncKind>{SyncKind.board};

  @override
  Future<void> applySync(List<SyncChange> changes) async {
    bool changed = false;
    for (final SyncChange change in changes) {
      if (change.deleted) {
        final int before = _boards.length;
        _boards.removeWhere(change.isFor);
        changed |= _boards.length != before;
      } else if (change.data['board'] case final String board
          when !_boards.contains(board)) {
        _boards.add(board);
        changed = true;
      }
    }
    if (changed) {
      await _store();
    }
  }

  @override
  void dispose() {
    _sync.detach(this);
    super.dispose();
  }
}
