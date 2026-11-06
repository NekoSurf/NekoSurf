import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Favorite boards, in the order they were added.
class FavoriteProvider with ChangeNotifier {
  FavoriteProvider(this._prefs)
    : _boards = _prefs.getStringList(_key) ?? <String>[];

  static const String _key = 'favoriteBoards';

  final SharedPreferences _prefs;
  final List<String> _boards;

  List<String> get boards => List<String>.unmodifiable(_boards);

  bool contains(String board) => _boards.contains(board);

  Future<void> _add(String board) async {
    if (_boards.contains(board)) {
      return;
    }
    _boards.add(board);
    notifyListeners();
    await _prefs.setStringList(_key, _boards);
  }

  Future<void> _remove(String board) async {
    _boards.remove(board);
    notifyListeners();
    await _prefs.setStringList(_key, _boards);
  }

  Future<void> toggle(String board) =>
      contains(board) ? _remove(board) : _add(board);
}
