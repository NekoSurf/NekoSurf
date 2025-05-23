import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/bookmark.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BookmarksProvider with ChangeNotifier {
  BookmarksProvider(this.list) {
    loadPreferences();
  }

  List<String> list = [];
  Sort sort = Sort.byNewest;

  Future<void> loadPreferences() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    List<String>? bookmarksPrefs = prefs.getStringList('favoriteThreads');

    bookmarksPrefs ??= [];

    list = bookmarksPrefs;

    notifyListeners();
  }

  Iterable<String> getBookmarks() {
    if (sort == Sort.byNewest)
      return list.reversed;
    else
      return list;
  }

  Future<void> addBookmarks(Bookmark? favorite) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    list.add(json.encode(favorite));

    prefs.setStringList('favoriteThreads', list);

    notifyListeners();
  }

  Future<void> removeBookmarks(
    Bookmark? favorite,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    list.remove(json.encode(favorite));

    prefs.setStringList('favoriteThreads', list);

    notifyListeners();
  }

  Future<void> clearBookmarks() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    list = [];

    prefs.setStringList('favoriteThreads', list);

    notifyListeners();
  }

  void setSort(Sort sortBy) {
    sort = sortBy;

    notifyListeners();
  }
}
