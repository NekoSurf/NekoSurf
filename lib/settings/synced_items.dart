import 'dart:convert';

import 'package:flutter_chan/board/favorite_model.dart';
import 'package:flutter_chan/bookmarks/bookmark.dart';
import 'package:flutter_chan/bookmarks/bookmarks_model.dart';
import 'package:flutter_chan/history/history_model.dart';
import 'package:flutter_chan/history/thread_memory.dart';
import 'package:flutter_chan/history/watched_posts_model.dart';
import 'package:flutter_chan/saved/saved_attachment.dart';
import 'package:flutter_chan/saved/saved_attachments_model.dart';
import 'package:flutter_chan/saved/saved_folders.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/sync/sync_items.dart';
import 'package:flutter_chan/thread/post_hiding.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Everything iCloud sync keeps, as it's stored on this device, with the
/// Saved tab's files where they are without asking for access: what
/// CloudSync.storedItems is.
Future<List<SyncItem>> storedSyncItems(SharedPreferences prefs) async =>
    localSyncItems(prefs, await openSavedFolders(ask: false));

List<T> _decodedList<T>(
  SharedPreferences prefs,
  String key,
  T? Function(String) parse,
) => <T>[
  for (final String raw in prefs.getStringList(key) ?? const <String>[])
    ?_tryParse(raw, parse),
];

T? _tryParse<T>(String raw, T? Function(String) parse) {
  try {
    return parse(raw);
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> _json(String raw) =>
    jsonDecode(raw) as Map<String, dynamic>;

/// Everything kept in sync, as it's stored in [prefs], with the Saved tab's
/// files in [folders].
List<SyncItem> localSyncItems(
  SharedPreferences prefs,
  SavedFolders folders,
) => <SyncItem>[
  for (final String key in SettingsProvider.syncedKeys)
    if (prefs.get(key) case final Object value) settingSyncItem(key, value),
  for (final String pattern
      in prefs.getStringList(SettingsProvider.hiddenPatternsKey) ??
          const <String>[])
    threadFilterSyncItem(pattern),
  for (final PostFilter filter in _decodedList(
    prefs,
    SettingsProvider.postFiltersKey,
    PostFilter.parse,
  ))
    postFilterSyncItem(filter),
  for (final String board
      in prefs.getStringList(FavoriteProvider.storageKey) ?? const <String>[])
    boardSyncItem(board),
  for (final Bookmark bookmark in _decodedList(
    prefs,
    BookmarksProvider.storageKey,
    (String raw) => Bookmark.fromJson(_json(raw)),
  ))
    bookmarkSyncItem(bookmark),
  for (final HistoryThread thread in _decodedList(
    prefs,
    HistoryProvider.storageKey,
    (String raw) => HistoryThread.fromJson(_json(raw)),
  ))
    historySyncItem(thread),
  for (final (int thread, ThreadMemory memory)
      in WatchedPostsProvider.storedMemories(prefs))
    threadMemorySyncItem(thread, memory),
  for (final SavedAttachment attachment in _decodedList(
    prefs,
    SavedAttachmentsProvider.storageKey,
    SavedAttachment.fromStored,
  ))
    // Not placeholders, whose files are still in iCloud.
    if (!_placeholderIds(prefs).contains(attachment.id))
      savedSyncItem(attachment, folders),
];

/// Which saved attachments are placeholders (see SavedAttachmentsProvider).
Set<String> _placeholderIds(SharedPreferences prefs) {
  try {
    final Object? decoded = jsonDecode(
      prefs.getString(SavedAttachmentsProvider.placeholdersKey) ?? '{}',
    );
    return decoded is Map ? decoded.keys.cast<String>().toSet() : const {};
  } on FormatException {
    return const {};
  }
}
