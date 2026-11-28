import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/saved/download_folder.dart';
import 'package:flutter_chan/settings/backup.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/thread/thread_posts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('a folder per thread', () {
    test('is named by number and subject', () {
      expect(threadFolderName(123456, 'Cats'), '123456 - Cats');
    });

    test("is just the number when there's nothing to name it by", () {
      expect(threadFolderName(123456, null), '123456');
      expect(threadFolderName(123456, '  ?? '), '123456');
    });

    test("leaves out what file names can't have", () {
      expect(
        threadFolderName(1, 'a/b\\c: "d"* <e>|f?\nnext line.'),
        '1 - a b c d e f next line',
      );
    });

    test('is cut short when the title is long', () {
      final String name = threadFolderName(123456, 'word ' * 50);
      expect(name.length, lessThanOrEqualTo(80));
      expect(name, startsWith('123456 - word word'));
      expect(name, isNot(endsWith(' ')));
    });

    test("takes the thread's first post's subject, or its start", () {
      Post op(String? sub, String com) => Post.fromJson(<String, dynamic>{
        'no': 42,
        'resto': 0,
        'sub': sub,
        'com': com,
      }, 'g');
      ThreadPosts thread(List<Post> posts) =>
          ThreadPosts(board: 'g', number: 42, posts: posts);

      expect(threadFolderOf(thread([op('Cats', 'meow')])), '42 - Cats');
      expect(threadFolderOf(thread([op(null, 'meow')])), '42 - meow');
      expect(threadFolderOf(thread(<Post>[])), '42');
    });
  });

  test('the picked folder is shown by its path', () {
    const String tree = 'content://com.android.externalstorage.documents/tree/';
    expect(
      downloadFolderLabel('${tree}primary%3ADownload%2FNekoSurf'),
      'Download/NekoSurf',
    );
    expect(downloadFolderLabel('${tree}primary%3A'), 'Phone storage');
    expect(downloadFolderLabel('${tree}1A2B-3C4D%3APics'), 'SD card/Pics');
  });

  group('where Save to Photos goes', () {
    late SettingsProvider settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = SettingsProvider(await SharedPreferences.getInstance());
    });

    test('is Pictures and Movies by default, without thread folders', () {
      final PhotosPlace place = PhotosPlace.of(settings, threadFolder: '1');
      expect(place.folder, isNull);
      expect(place.subfolder, isNull);
    });

    test(
      "is the picked folder, in the thread's with a folder per thread",
      () async {
        await settings.downloadFolder.set('content://picked');
        await settings.folderPerThread.set(true);
        final PhotosPlace place = PhotosPlace.of(settings, threadFolder: '1');
        expect(place.folder, 'content://picked');
        expect(place.subfolder, '1');
        expect(PhotosPlace.of(settings).subfolder, isNull);
      },
    );

    test("the picked folder is this phone's own, not backed up", () {
      expect(isLocalPreference(SettingsProvider.downloadFolderKey), isTrue);
      expect(isLocalPreference('folderPerThread'), isFalse);
    });
  });
}
