import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_chan/bookmarks/bookmark.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bookmarked threads, one per thread (by board and number), oldest first
/// as stored.
class BookmarksProvider with ChangeNotifier {
  BookmarksProvider(this._prefs) {
    final Set<String> seen = {};
    for (final String raw in _prefs.getStringList(_key) ?? const []) {
      try {
        final Bookmark bookmark = Bookmark.fromJson(
          json.decode(raw) as Map<String, dynamic>,
        );
        // Older versions could store a thread twice, with different details.
        if (seen.add(bookmark.key)) {
          _bookmarks.add(bookmark);
        }
      } catch (_) {
        // Skip corrupt entries.
      }
    }
  }

  static const String _key = 'favoriteThreads';

  final SharedPreferences _prefs;
  final List<Bookmark> _bookmarks = [];
  bool newestFirst = true;

  List<Bookmark> get bookmarks => newestFirst
      ? _bookmarks.reversed.toList(growable: false)
      : List.unmodifiable(_bookmarks);

  bool isBookmarked(Bookmark bookmark) =>
      _bookmarks.any((b) => b.key == bookmark.key);

  Future<void> addBookmark(Bookmark bookmark) async {
    if (isBookmarked(bookmark)) {
      return;
    }
    _bookmarks.add(bookmark);
    await _save();
  }

  Future<void> removeBookmark(Bookmark bookmark) async {
    _bookmarks.removeWhere((b) => b.key == bookmark.key);
    await _save();
  }

  Future<void> toggleBookmark(Bookmark bookmark) =>
      isBookmarked(bookmark) ? removeBookmark(bookmark) : addBookmark(bookmark);

  Future<void> clearBookmarks() async {
    _bookmarks.clear();
    await _save();
  }

  void setNewestFirst(bool value) {
    newestFirst = value;
    notifyListeners();
  }

  Future<void> _save() async {
    notifyListeners();
    await _prefs.setStringList(_key, [
      for (final Bookmark bookmark in _bookmarks) json.encode(bookmark),
    ]);
  }
}
