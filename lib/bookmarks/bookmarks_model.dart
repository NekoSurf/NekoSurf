import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_chan/bookmarks/bookmark.dart';
import 'package:flutter_chan/sync/cloud_sync.dart';
import 'package:flutter_chan/sync/sync_items.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [bookmark], as iCloud sync keeps it.
SyncItem bookmarkSyncItem(Bookmark bookmark) =>
    SyncItem(SyncKind.bookmark, bookmark.key, bookmark.toJson());

/// Which of two goes first: the same on every device.
int _byAddedAt(Bookmark a, Bookmark b) {
  final int byTime = (a.addedAt ?? 0).compareTo(b.addedAt ?? 0);
  return byTime != 0 ? byTime : a.key.compareTo(b.key);
}

/// Bookmarked threads, one per thread (by board and number), oldest first:
/// by when each was bookmarked ([Bookmark.addedAt]), the same order on
/// every device with iCloud sync.
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
    _numberOlderOnes();
    _sync.attach(this);
  }

  /// Gives bookmarks from before [Bookmark.addedAt] was kept a number in
  /// the order they're stored, and sends them, so every device has the same
  /// numbers: the order of the last to send them.
  void _numberOlderOnes() {
    if (_bookmarks.every((b) => b.addedAt != null)) {
      return;
    }
    final List<Bookmark> numbered = <Bookmark>[];
    for (int i = 0; i < _bookmarks.length; i++) {
      if (_bookmarks[i].addedAt == null) {
        _bookmarks[i] = _bookmarks[i].addedAtTime(i + 1);
        numbered.add(_bookmarks[i]);
      }
    }
    _bookmarks.sort(_byAddedAt);
    _sync.putAll(<SyncItem>[for (final b in numbered) bookmarkSyncItem(b)]);
    unawaited(_save());
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
    final Bookmark added = bookmark.addedAtTime(
      DateTime.now().millisecondsSinceEpoch,
    );
    _bookmarks.add(added);
    _bookmarks.sort(_byAddedAt);
    _sync.put(bookmarkSyncItem(added));
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
      Bookmark bookmark;
      try {
        bookmark = Bookmark.fromJson(change.data.cast<String, dynamic>());
      } catch (_) {
        continue;
      }
      final int at = _bookmarks.indexWhere((b) => b.key == bookmark.key);
      // One from an older NekoSurf doesn't say when: as it was here, or now.
      if (bookmark.addedAt == null) {
        bookmark = bookmark.addedAtTime(
          at < 0
              ? DateTime.now().millisecondsSinceEpoch
              : _bookmarks[at].addedAt ?? 0,
        );
      }
      if (at < 0) {
        _bookmarks.add(bookmark);
      } else {
        _bookmarks[at] = bookmark;
      }
    }
    _bookmarks.sort(_byAddedAt);
    await _save();
  }

  @override
  void dispose() {
    _sync.detach(this);
    super.dispose();
  }
}
