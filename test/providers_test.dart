import 'dart:convert';

import 'package:flutter_chan/Models/bookmark.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/bookmarks_model.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/blocs/watched_posts_model.dart';
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
    test(
      'threads are nested until flat is chosen, which is remembered',
      () async {
        SharedPreferences.setMockInitialValues({});
        final SharedPreferences prefs = await SharedPreferences.getInstance();

        final SettingsProvider settings = SettingsProvider(prefs);
        expect(settings.getThreadLayout(), ThreadLayout.nested);

        await settings.setThreadLayout(ThreadLayout.flat);
        expect(SettingsProvider(prefs).getThreadLayout(), ThreadLayout.flat);
      },
    );

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

  group('WatchedPostsProvider', () {
    Future<WatchedPostsProvider> watchedProvider() async {
      final WatchedPostsProvider watched = WatchedPostsProvider(
        await SharedPreferences.getInstance(),
      );
      addTearDown(watched.dispose);
      // Let the cleanup it starts with finish.
      await Future<void>.delayed(Duration.zero);
      return watched;
    }

    test('a thread opened for the first time has nothing new', () async {
      SharedPreferences.setMockInitialValues({});
      final WatchedPostsProvider watched = await watchedProvider();

      watched.noteThreadPosts(1, [1, 2, 3]);

      expect(watched.unseenPosts(1), isEmpty);
    });

    test('posts after the newest known are new, until seen', () async {
      SharedPreferences.setMockInitialValues({});
      final WatchedPostsProvider watched = await watchedProvider();

      watched.noteThreadPosts(1, [1, 2, 3]);
      watched.noteThreadPosts(1, [1, 2, 3, 4, 5]);
      expect(watched.unseenPosts(1), {4, 5});

      watched.markPostsSeen(1, [4]);
      expect(watched.unseenPosts(1), {5});
    });

    test('a thread read before agrees with its new reply count', () async {
      SharedPreferences.setMockInitialValues({});
      final WatchedPostsProvider watched = await watchedProvider();

      await watched.markAsWatched(postIndex: 2, thread: 1);
      watched.noteThreadPosts(1, [10, 11, 12, 13, 14]);

      expect(watched.unseenPosts(1), {13, 14});
      expect(watched.newReplies(1, 4), 2);
    });

    test('counts what is unseen, and what was posted since loading', () async {
      SharedPreferences.setMockInitialValues({});
      final WatchedPostsProvider watched = await watchedProvider();

      await watched.markAsWatched(postIndex: 4, thread: 1);
      watched.noteThreadPosts(1, [1, 2, 3]);
      watched.noteThreadPosts(1, [1, 2, 3, 4, 5]);

      // How far it was read doesn't matter: 4 and 5 still haven't been seen.
      expect(watched.newReplies(1, 4), 2);
      expect(watched.newReplies(1, 5), 3);

      watched.markPostsSeen(1, [4]);
      expect(watched.newReplies(1, 4), 1);

      watched.markPostsSeen(1, [5]);
      expect(watched.newReplies(1, 4), 0);
    });

    test('a deleted post is no longer new', () async {
      SharedPreferences.setMockInitialValues({});
      final WatchedPostsProvider watched = await watchedProvider();

      watched.noteThreadPosts(1, [1]);
      watched.noteThreadPosts(1, [1, 2, 3]);
      watched.noteThreadPosts(1, [1, 3]);

      expect(watched.unseenPosts(1), {3});
    });

    test('new posts are remembered, and cleared with watched posts', () async {
      SharedPreferences.setMockInitialValues({});
      final WatchedPostsProvider watched = await watchedProvider();

      await watched.markAsWatched(postIndex: 0, thread: 1);
      watched.noteThreadPosts(1, [1]);
      watched.noteThreadPosts(1, [1, 2]);
      await watched.clearOldWatchedPosts();

      final WatchedPostsProvider again = await watchedProvider();
      expect(again.unseenPosts(1), {2});

      await again.clearAllWatchedPosts();
      expect(again.unseenPosts(1), isEmpty);
    });

    test('counts replies read apart from where to resume', () async {
      SharedPreferences.setMockInitialValues({});
      final WatchedPostsProvider watched = WatchedPostsProvider(
        await SharedPreferences.getInstance(),
      );
      addTearDown(watched.dispose);

      // With replies nested, the last reply listed can be an early post.
      await watched.markAsWatched(postIndex: 3, seen: 10, thread: 1);

      expect(watched.getLatestWatchedPosts(1)?.postIndex, 3);
      expect(watched.newReplies(1, 10), 0);
      expect(watched.newReplies(1, 12), 2);
    });

    test('takes the place in the thread as the count otherwise', () async {
      SharedPreferences.setMockInitialValues({});
      final WatchedPostsProvider watched = WatchedPostsProvider(
        await SharedPreferences.getInstance(),
      );
      addTearDown(watched.dispose);

      await watched.markAsWatched(postIndex: 4, thread: 1);

      expect(watched.newReplies(1, 10), 6);
    });
  });
}
