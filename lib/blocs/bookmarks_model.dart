import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/bookmark.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BookmarksProvider with ChangeNotifier {
  BookmarksProvider(this._prefs) {
    list = _prefs.getStringList(_key) ?? [];
  }

  static const String _key = 'favoriteThreads';

  final SharedPreferences _prefs;
  List<String> list = [];
  Sort sort = Sort.byNewest;

  Iterable<String> getBookmarks() {
    if (sort == Sort.byNewest) {
      return list.reversed;
    } else {
      return list;
    }
  }

  Future<void> addBookmarks(Bookmark? favorite) async {
    list.add(json.encode(favorite));
    await _save();
  }

  Future<void> removeBookmarks(Bookmark? favorite) async {
    list.remove(json.encode(favorite));
    await _save();
  }

  Future<void> clearBookmarks() async {
    list = [];
    await _save();
  }

  void setSort(Sort sortBy) {
    sort = sortBy;

    notifyListeners();
  }

  Future<void> _save() async {
    notifyListeners();
    await _prefs.setStringList(_key, list);
  }
}
