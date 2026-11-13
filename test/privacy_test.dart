import 'dart:convert';
import 'dart:io';

import 'package:flutter_chan/chan/board.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/history/history_model.dart';
import 'package:flutter_chan/saved/saved_folders.dart';
import 'package:flutter_chan/settings/backup.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Board _board(String code, {required bool nsfw}) =>
    Board(board: code, title: code, wsBoard: nsfw ? 0 : 1);

void main() {
  late SharedPreferences prefs;
  late SettingsProvider settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    settings = SettingsProvider(prefs);
  });

  group('NSFW boards', () {
    test('are hidden, by what the last board list said', () async {
      settings.rememberBoards([
        _board('g', nsfw: false),
        _board('b', nsfw: true),
      ]);
      expect(settings.hidesBoard('b'), isTrue);
      expect(settings.hidesBoard('g'), isFalse);
      // Known on the next launch, before the list loads.
      expect(SettingsProvider(prefs).hidesBoard('b'), isTrue);

      await settings.allowNSFW.set(true);
      expect(settings.hidesBoard('b'), isFalse);
    });

    test('each time: shown with the flame, until the app is closed', () async {
      settings.rememberBoards([_board('b', nsfw: true)]);
      await settings.allowNSFW.set(true);
      await settings.nsfwEachSession.set(true);
      expect(settings.showsNsfw, isFalse);
      expect(settings.hidesBoard('b'), isTrue);

      settings.setNsfwSession(true);
      expect(settings.showsNsfw, isTrue);
      expect(settings.hidesBoard('b'), isFalse);

      // Kept in memory only: the next launch starts with them hidden.
      expect(SettingsProvider(prefs).showsNsfw, isFalse);
    });
  });

  group('history only while the app is open', () {
    Post op(int no) => Post(board: 'g', no: no, time: 1700000000);

    test('is never stored, and is forgotten when the app is left', () async {
      final HistoryProvider history = HistoryProvider(prefs, settings);
      addTearDown(history.dispose);
      await history.recordThread(op(1));
      expect(prefs.getStringList(HistoryProvider.storageKey), hasLength(1));

      await history.setSessionOnly(true);
      expect(prefs.getStringList(HistoryProvider.storageKey), isNull);
      await history.recordThread(op(2));
      expect(history.threads.map((t) => t.no), [2, 1]);
      expect(prefs.getStringList(HistoryProvider.storageKey), isNull);

      history.forgetSession();
      expect(history.threads, isEmpty);
    });

    test('kept as before, leaving the app forgets nothing', () async {
      final HistoryProvider history = HistoryProvider(prefs, settings);
      addTearDown(history.dispose);
      await history.recordThread(op(1));
      history.forgetSession();
      expect(history.threads, hasLength(1));
    });
  });

  group('saved files out of Files', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('privacy'));
    tearDown(() => dir.deleteSync(recursive: true));

    String stored(String fileName) => jsonEncode({
      'savedAttachmentType': 'image',
      'fileName': fileName,
      'thumbnail': fileName,
      'id': fileName,
    });

    test('moves only the saved files, and keeps where they are', () async {
      final String shown = '${dir.path}/Documents';
      final String private = '${dir.path}/savedMedia';
      Directory(shown).createSync();
      File('$shown/cat.png').writeAsStringSync('meow');
      File('$shown/not saved.txt').writeAsStringSync('mine');
      await prefs.setStringList('savedAttachments', [
        stored('cat.png'),
        // Still in iCloud: nothing to move.
        stored('dog.png'),
      ]);

      final List<(int, int)> progress = [];
      await moveSavedFilesBetween(
        prefs,
        hidden: true,
        from: shown,
        to: private,
        onProgress: (done, total) => progress.add((done, total)),
      );
      expect(progress, [(0, 2), (1, 2), (2, 2)]);
      expect(File('$private/cat.png').readAsStringSync(), 'meow');
      expect(File('$shown/cat.png').existsSync(), isFalse);
      expect(File('$shown/not saved.txt').existsSync(), isTrue);
      expect(prefs.getBool(savedFilesHiddenKey), isTrue);
      // Done: nothing to finish on the next launch.
      expect(prefs.getBool(savedFilesMovingKey), isNull);

      await moveSavedFilesBetween(
        prefs,
        hidden: false,
        from: private,
        to: shown,
      );
      expect(File('$shown/cat.png').readAsStringSync(), 'meow');
      expect(prefs.getBool(savedFilesHiddenKey), isFalse);
    });

    test("where they are is this phone's own, not backed up", () {
      expect(isLocalPreference(savedFilesHiddenKey), isTrue);
      expect(isLocalPreference(savedFilesMovingKey), isTrue);
    });
  });
}
