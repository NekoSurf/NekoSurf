import 'dart:convert';

import 'package:flutter_chan/Models/bookmark.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/bookmarks_model.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _stored(Bookmark bookmark) => json.encode(bookmark);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BookmarksProvider', () {
    test('keeps one bookmark per thread, whatever its details', () async {
      SharedPreferences.setMockInitialValues({
        'favoriteThreads': [
          _stored(Bookmark(board: 'g', no: 1, sub: 'Old title')),
          _stored(Bookmark(board: 'g', no: 1, sub: 'New title')),
          _stored(Bookmark(board: 'g', no: 2)),
          'not json',
        ],
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final BookmarksProvider bookmarks = BookmarksProvider(prefs);

      // Newest first; the duplicate and the corrupt entry are gone.
      expect(bookmarks.bookmarks.map((b) => b.key), ['g/2', 'g/1']);
      expect(bookmarks.bookmarks.last.sub, 'Old title');

      // Matched by thread, not by the title or image it was saved with.
      final Bookmark same = Bookmark(board: 'g', no: 1, com: 'Changed');
      expect(bookmarks.isBookmarked(same), isTrue);
      await bookmarks.addBookmark(same);
      expect(bookmarks.bookmarks, hasLength(2));

      await bookmarks.removeBookmark(same);
      expect(bookmarks.bookmarks.map((b) => b.key), ['g/2']);
      expect(prefs.getStringList('favoriteThreads'), [
        _stored(Bookmark(board: 'g', no: 2)),
      ]);
    });

    test('sorts oldest first on request', () async {
      SharedPreferences.setMockInitialValues({
        'favoriteThreads': [
          _stored(Bookmark(board: 'g', no: 1)),
          _stored(Bookmark(board: 'v', no: 2)),
        ],
      });
      final BookmarksProvider bookmarks = BookmarksProvider(
        await SharedPreferences.getInstance(),
      )..setSort(Sort.byOldest);

      expect(bookmarks.bookmarks.map((b) => b.key), ['g/1', 'v/2']);
    });
  });

  group('SettingsProvider', () {
    test('has the saved settings as soon as it exists', () async {
      SharedPreferences.setMockInitialValues({
        'boardSort': 'byReplyCount',
        'boardViewMode': 'no longer a mode',
        'allowNSFW': true,
        'watchedPostsRetentionDays': 30,
      });
      final SettingsProvider settings = SettingsProvider(
        await SharedPreferences.getInstance(),
      );

      expect(settings.getBoardSort(), Sort.byReplyCount);
      expect(settings.getBoardViewMode(), ViewMode.grid);
      expect(settings.getNSFW(), isTrue);
      expect(settings.getWatchedPostsRetentionDays(), 30);
      expect(settings.getTrackHistory(), isTrue);
    });

    test('saves changes and hides threads by pattern', () async {
      SharedPreferences.setMockInitialValues({});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final SettingsProvider settings = SettingsProvider(prefs);

      await settings.setBoardViewMode(ViewMode.list);
      await settings.addHiddenThreadPattern('linux');
      // Not a valid regex: matched as plain text instead.
      await settings.addHiddenThreadPattern('(unclosed');

      expect(prefs.getString('boardViewMode'), 'list');
      expect(prefs.getStringList('hiddenThreadPatterns'), [
        'linux',
        '(unclosed',
      ]);
      expect(settings.isThreadHidden(Post(sub: 'Linux general')), isTrue);
      expect(settings.isThreadHidden(Post(com: 'an (unclosed one')), isTrue);
      expect(settings.isThreadHidden(Post(sub: 'Windows')), isFalse);
    });
  });
}
