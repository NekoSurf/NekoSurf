import 'dart:convert';

import 'package:flutter_chan/Models/bookmark.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final bookmarksProvider =
    NotifierProvider<BookmarksNotifier, BookmarksState>(BookmarksNotifier.new);

class BookmarksState {
  const BookmarksState({
    this.list = const [],
    this.sort = Sort.byNewest,
  });

  final List<String> list;
  final Sort sort;

  Iterable<String> getBookmarks() {
    return sort == Sort.byNewest ? list.reversed : list;
  }

  BookmarksState copyWith({List<String>? list, Sort? sort}) {
    return BookmarksState(
      list: list ?? this.list,
      sort: sort ?? this.sort,
    );
  }
}

class BookmarksNotifier extends Notifier<BookmarksState> {
  @override
  BookmarksState build() {
    _loadPreferences();
    return const BookmarksState();
  }

  Future<void> _loadPreferences() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> bookmarksPrefs =
        prefs.getStringList('favoriteThreads') ?? [];
    state = state.copyWith(list: bookmarksPrefs);
  }

  Future<void> addBookmarks(Bookmark? favorite) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final updated = List<String>.from(state.list)..add(json.encode(favorite));
    prefs.setStringList('favoriteThreads', updated);
    state = state.copyWith(list: updated);
  }

  Future<void> removeBookmarks(Bookmark? favorite) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final updated = List<String>.from(state.list)
      ..remove(json.encode(favorite));
    prefs.setStringList('favoriteThreads', updated);
    state = state.copyWith(list: updated);
  }

  Future<void> clearBookmarks() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setStringList('favoriteThreads', []);
    state = state.copyWith(list: []);
  }

  void setSort(Sort sort) {
    state = state.copyWith(sort: sort);
  }
}
