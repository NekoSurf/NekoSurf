import 'dart:io';

import 'package:flutter_chan/bookmarks/bookmark.dart';
import 'package:flutter_chan/bookmarks/bookmarks_model.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/history/history_model.dart';
import 'package:flutter_chan/history/thread_copies.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;
  late ThreadCopies copies;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('thread_copies_test');
    copies = ThreadCopies(() async => dir);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Set<String> files() => <String>{
    for (final FileSystemEntity entity in dir.listSync())
      entity.uri.pathSegments.last,
  };

  test('a post reads back as it was', () {
    final Post post = Post(
      board: 'g',
      no: 2,
      sub: 'Title',
      com: 'Words',
      name: 'Anonymous',
      filename: 'cat',
      ext: '.jpg',
      w: 800,
      h: 600,
      tnW: 250,
      tnH: 187,
      tim: 1700000000123,
      time: 1700000000,
      resto: 1,
      country: 'FR',
      countryName: 'France',
      id: 'abcd1234',
      trip: '!trip',
      capcode: 'mod',
      spoiler: 1,
      archived: 1,
      closed: 1,
    );

    final Post read = Post.fromJson(post.toJson(), 'g');

    expect(read.toJson(), post.toJson());
    expect(read.board, 'g');
    expect(read.tnW, 250);
    expect(read.countryName, 'France');
  });

  test('keeps the latest copy of a thread, and when it was kept', () async {
    expect(await copies.read('g', 1), isNull);

    await copies.keep('g', 1, [Post(board: 'g', no: 1, com: 'first')]);
    final DateTime before = DateTime.now();
    await copies.keep('g', 1, [
      Post(board: 'g', no: 1, com: 'first'),
      Post(board: 'g', no: 2, com: 'second'),
    ]);

    final ThreadCopy? copy = await copies.read('g', 1);
    expect(
      [for (final Post post in copy!.posts) post.com],
      ['first', 'second'],
    );
    expect(copy.posts.last.board, 'g');
    expect(
      copy.savedAt.isAfter(before.subtract(const Duration(seconds: 1))),
      isTrue,
    );
    // Nothing half-written is left behind.
    expect(files(), {'g_1.json'});
  });

  test('a copy that cannot be read is as good as none', () async {
    File('${dir.path}/g_1.json').writeAsStringSync('{"posts": [');
    expect(await copies.read('g', 1), isNull);
  });

  test('keeps only the copies of the threads asked for', () async {
    await copies.keep('g', 1, [Post(board: 'g', no: 1)]);
    await copies.keep('g', 2, [Post(board: 'g', no: 2)]);
    await copies.keep('v', 1, [Post(board: 'v', no: 1)]);

    await copies.keepOnly({'g/2', 'a/5'});

    expect(files(), {'g_2.json'});
  });

  test('copies go with their bookmark or history entry', () async {
    SharedPreferences.setMockInitialValues({});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final BookmarksProvider bookmarks = BookmarksProvider(prefs);
    final HistoryProvider history = HistoryProvider(
      prefs,
      SettingsProvider(prefs),
    );
    await copies.keep('g', 1, [Post(board: 'g', no: 1)]);
    await copies.keep('g', 2, [Post(board: 'g', no: 2)]);
    await bookmarks.addBookmark(Bookmark.fromPost(Post(board: 'g', no: 1)));
    await history.recordThread(Post(board: 'g', no: 2));

    final void Function() stop = keepThreadCopiesOf(
      bookmarks,
      history,
      copies: copies,
    );
    addTearDown(stop);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(files(), {'g_1.json', 'g_2.json'});

    // Clearing history takes its copies with it, right away.
    await history.clear();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(files(), {'g_1.json'});
  });
}
