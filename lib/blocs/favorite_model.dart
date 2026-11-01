import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Favorite boards, in the order they were added.
class FavoriteProvider with ChangeNotifier {
  FavoriteProvider(this._prefs)
    : list = _prefs.getStringList(_key) ?? <String>[];

  static const String _key = 'favoriteBoards';

  final SharedPreferences _prefs;
  List<String> list;

  List<String> getFavorites() => list;

  Future<void> addFavorites(String board) async {
    if (list.contains(board)) {
      return;
    }
    list.add(board);
    notifyListeners();
    await _prefs.setStringList(_key, list);
  }

  Future<void> removeFavorites(String board) async {
    list.remove(board);
    notifyListeners();
    await _prefs.setStringList(_key, list);
  }
}
