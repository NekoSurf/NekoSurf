import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_chan/bookmarks/bookmark.dart';
import 'package:flutter_chan/sync/cloud_sync.dart';
import 'package:flutter_chan/sync/sync_items.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [bookmark], as iCloud sync keeps it.
SyncItem bookmarkSyncItem(Bookmark bookmark) =>
    SyncItem(SyncKind.bookmark, bookmark.key, bookmark.toJson());

/// Bookmarked threads, one per thread (by board and number), oldest first
/// as stored.
class BookmarksProvider with ChangeNotifier implements SyncTarget {
  BookmarksProvider(this._prefs, {CloudSync? sync})
    : _sync = sync ?? CloudSync.instance {
    final Set<String> seen = {};
    for (final String raw in _prefs.getStringList(storageKey) ?? const []) {
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
    _sync.attach(this);
  }

  /// Where the bookmarks are kept in SharedPreferences.
  static const String storageKey = 'favoriteThreads';

  final SharedPreferences _prefs;
  final CloudSync _sync;
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
    _sync.put(bookmarkSyncItem(bookmark));
    await _save();
  }

  Future<void> removeBookmark(Bookmark bookmark) async {
    _bookmarks.removeWhere((b) => b.key == bookmark.key);
    _sync.remove(SyncKind.bookmark, bookmark.key);
    await _save();
  }

  Future<void> toggleBookmark(Bookmark bookmark) =>
      isBookmarked(bookmark) ? removeBookmark(bookmark) : addBookmark(bookmark);

  Future<void> clearBookmarks() async {
    _sync.removeAll(SyncKind.bookmark, [for (final b in _bookmarks) b.key]);
    _bookmarks.clear();
    await _save();
  }

  void setNewestFirst(bool value) {
    newestFirst = value;
    notifyListeners();
  }

  Future<void> _save() async {
    notifyListeners();
    await _prefs.setStringList(storageKey, [
      for (final Bookmark bookmark in _bookmarks) json.encode(bookmark),
    ]);
  }

  @override
  Set<SyncKind> get syncKinds => const <SyncKind>{SyncKind.bookmark};

  @override
  Future<void> applySync(List<SyncChange> changes) async {
    for (final SyncChange change in changes) {
      if (change.deleted) {
        _bookmarks.removeWhere((Bookmark b) => change.isFor(b.key));
        continue;
      }
      final Bookmark bookmark;
      try {
        bookmark = Bookmark.fromJson(change.data.cast<String, dynamic>());
      } catch (_) {
        continue;
      }
      final int at = _bookmarks.indexWhere((b) => b.key == bookmark.key);
      if (at < 0) {
        _bookmarks.add(bookmark);
      } else {
        _bookmarks[at] = bookmark;
      }
    }
    await _save();
  }

  @override
  void dispose() {
    _sync.detach(this);
    super.dispose();
  }
}
