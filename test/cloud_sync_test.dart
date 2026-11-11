import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_chan/board/favorite_model.dart';
import 'package:flutter_chan/bookmarks/bookmark.dart';
import 'package:flutter_chan/bookmarks/bookmarks_model.dart';
import 'package:flutter_chan/history/history_model.dart';
import 'package:flutter_chan/history/watched_posts_model.dart';
import 'package:flutter_chan/saved/saved_attachments_model.dart';
import 'package:flutter_chan/saved/saved_folders.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/settings/synced_items.dart';
import 'package:flutter_chan/sync/cloud_sync.dart';
import 'package:flutter_chan/sync/sync_items.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('nekosurf/cloudsync');

  late Directory dir;
  late SavedFolders folders;
  // The Swift side, as far as Dart sees it.
  late List<Map<String, Object?>> inbox;
  late List<Map<String, Object?>> cloud;
  late List<Map<Object?, Object?>> sent;
  late List<String> deleted;
  late List<String> calls;
  String? fetchFails;
  bool signInOnStart = false;
  Completer<void>? sending;
  int seq = 0;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('cloud_sync_test');
    folders = SavedFolders(
      media: '${dir.path}/media',
      thumbnails: '${dir.path}/thumbs',
    );
    Directory(folders.media).createSync();
    Directory(folders.thumbnails).createSync();
    inbox = [];
    cloud = [];
    sent = [];
    deleted = [];
    calls = [];
    fetchFails = null;
    signInOnStart = false;
    sending = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'fetch':
              if (fetchFails != null) {
                throw PlatformException(code: fetchFails!);
              }
              for (final Map<String, Object?> entry in cloud) {
                inbox.add({...entry, 'seq': ++seq});
              }
              cloud.clear();
              return null;
            case 'takeInbox':
              return List<Object?>.of(inbox);
            case 'ackInbox':
              inbox.removeWhere(
                (e) => (e['seq']! as int) <= (call.arguments as int),
              );
              return null;
            case 'save':
              sent.addAll((call.arguments as List).cast());
              return null;
            case 'delete':
              deleted.addAll((call.arguments as List).cast());
              return null;
            case 'start':
              // As a sync engine does that starts without saved state.
              if (signInOnStart) {
                signInOnStart = false;
                inbox.add({
                  'event': 'signedIn',
                  'seq': ++seq,
                  'deleted': false,
                });
              }
              return null;
            case 'send':
              // Saved files can take minutes to go up.
              await sending?.future;
              return null;
            case 'stop':
              inbox.clear();
              return null;
            case 'status':
              return <String, Object?>{};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    dir.deleteSync(recursive: true);
  });

  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  /// A change made on another device, as the Swift side hands it over.
  Map<String, Object?> change(
    SyncKind kind,
    String key,
    Map<String, Object?> data, {
    String? media,
  }) => {
    'id': syncId(kind, key),
    'kind': kind.name,
    'key': key,
    'data': jsonEncode(data),
    'modifiedAt': DateTime(2026).millisecondsSinceEpoch,
    'media': media,
    'deleted': false,
  };

  Map<String, Object?> deletion(SyncKind kind, String key) => {
    'id': syncId(kind, key),
    'deleted': true,
  };

  Map<String, Object?> bookmark(String board, int no) => {
    'board': board,
    'no': no,
  };

  String savedEntry(String fileName, String id) => jsonEncode({
    'savedAttachmentType': 'image',
    'fileName': fileName,
    'thumbnail': fileName,
    'id': id,
  });

  /// An app's worth of what syncs, on [prefs].
  Future<
    ({
      CloudSync sync,
      SettingsProvider settings,
      BookmarksProvider bookmarks,
      HistoryProvider history,
      SavedAttachmentsProvider saved,
      FavoriteProvider boards,
      WatchedPostsProvider watched,
    })
  >
  app(SharedPreferences prefs) async {
    final CloudSync sync = CloudSync.forTesting(
      (SharedPreferences prefs) async => localSyncItems(prefs, folders),
    );
    await sync.load(prefs);
    final SettingsProvider settings = SettingsProvider(prefs, sync: sync);
    return (
      sync: sync,
      settings: settings,
      bookmarks: BookmarksProvider(prefs, sync: sync),
      history: HistoryProvider(prefs, settings, sync: sync),
      saved: SavedAttachmentsProvider(
        prefs,
        sync: sync,
        syncFolders: () async => folders,
      ),
      boards: FavoriteProvider(prefs, sync: sync),
      watched: WatchedPostsProvider(prefs, settings, sync: sync),
    );
  }

  Set<String> sentIds() => {for (final item in sent) item['id']! as String};

  test('record ids say what they are of, unless the key is too long', () {
    expect(syncKeyOf(syncId(SyncKind.bookmark, 'wsg/123')), 'wsg/123');
    expect(syncKindOf(syncId(SyncKind.saved, '123')), SyncKind.saved);
    final String long = 'ä' * 300;
    final String id = syncId(SyncKind.threadFilter, long);
    expect(id.length, lessThan(255));
    expect(syncKeyOf(id), isNull);
    expect(syncKindOf(id), SyncKind.threadFilter);
  });

  test('nothing is sent until iCloud sync is turned on', () async {
    final a = await app(await prefsWith({}));
    await a.bookmarks.addBookmark(Bookmark(board: 'g', no: 1));
    await a.settings.themeColor.set(ThemeColor.violet);
    await pumpEventQueue();

    expect(a.sync.isOn, isFalse);
    expect(calls, isNot(contains('save')));
  });

  test("turning on brings in what's in iCloud, then sends what it didn't "
      'have', () async {
    final File media = File('${dir.path}/incoming-cat')
      ..writeAsStringSync('meow');
    File('${folders.media}/cat.png').writeAsStringSync('a cat of this phone');
    cloud = [
      change(SyncKind.bookmark, 'wsg/1', bookmark('wsg', 1)),
      change(SyncKind.setting, 'themeColor', {'value': 'violet'}),
      change(
        SyncKind.saved,
        '111',
        jsonDecode(savedEntry('cat.png', '111')) as Map<String, Object?>,
        media: media.path,
      ),
    ];
    final a = await app(
      await prefsWith({
        'themeColor': 'cyan',
        'videoCacheMegabytes': 500,
        'favoriteThreads': [jsonEncode(bookmark('g', 2))],
        'savedAttachments': [savedEntry('cat.png', '222')],
      }),
    );

    await a.sync.turnOn();

    expect(a.sync.isOn, isTrue);
    expect(a.sync.lastBroughtIn, 3);
    expect(a.bookmarks.bookmarks.map((b) => b.key), {'wsg/1', 'g/2'});
    expect(a.settings.themeColor.value, ThemeColor.violet);
    expect(a.saved.attachments.map((s) => s.fileName), [
      'cat.png',
      'cat (2).png',
    ]);
    expect(File('${folders.media}/cat (2).png').readAsStringSync(), 'meow');
    // What iCloud had stays as it was; this phone's own goes up.
    expect(sentIds(), {
      syncId(SyncKind.bookmark, 'g/2'),
      syncId(SyncKind.saved, '222'),
    });
    final Map<Object?, Object?> cat = sent.firstWhere(
      (item) => item['kind'] == 'saved',
    );
    expect(cat['media'], '${folders.media}/cat.png');
    expect(inbox, isEmpty);
  });

  test("an engine's first sign-in doesn't send what's here before what's "
      'in iCloud is applied', () async {
    signInOnStart = true;
    cloud = [
      change(SyncKind.setting, 'themeColor', {'value': 'violet'}),
    ];
    final a = await app(
      await prefsWith({
        'themeColor': 'cyan',
        'favoriteThreads': [jsonEncode(bookmark('g', 2))],
      }),
    );

    await a.sync.turnOn();
    await pumpEventQueue();

    expect(a.settings.themeColor.value, ThemeColor.violet);
    // Sent once, without the setting iCloud had.
    expect(sent.map((item) => item['id']), [syncId(SyncKind.bookmark, 'g/2')]);
    expect(inbox, isEmpty);
  });

  test("turning on fails, and stays off, if iCloud can't be reached", () async {
    fetchFails = 'offline';
    final a = await app(await prefsWith({}));

    await expectLater(a.sync.turnOn(), throwsA(isA<SyncFailed>()));
    expect(a.sync.isOn, isFalse);
    expect(calls, contains('stop'));
  });

  test('while on, changes here go out, but not device settings', () async {
    final a = await app(await prefsWith({}));
    await a.sync.turnOn();
    sent.clear();

    await a.bookmarks.addBookmark(Bookmark(board: 'g', no: 1));
    await a.settings.themeColor.set(ThemeColor.violet);
    await a.settings.videoCacheMegabytes.set(800);
    await a.boards.toggle('wsg');
    await a.settings.addHiddenThreadPattern('spoilers');
    await pumpEventQueue();
    expect(sentIds(), {
      syncId(SyncKind.bookmark, 'g/1'),
      syncId(SyncKind.setting, 'themeColor'),
      syncId(SyncKind.board, 'wsg'),
      syncId(SyncKind.threadFilter, 'spoilers'),
    });

    await a.bookmarks.removeBookmark(Bookmark(board: 'g', no: 1));
    await a.boards.toggle('wsg');
    await pumpEventQueue();
    expect(deleted, [
      syncId(SyncKind.bookmark, 'g/1'),
      syncId(SyncKind.board, 'wsg'),
    ]);
  });

  test('changes made elsewhere are applied, and not sent back', () async {
    File('${folders.media}/dog.png').writeAsStringSync('woof');
    final a = await app(
      await prefsWith({
        'favoriteThreads': [jsonEncode(bookmark('g', 2))],
        'savedAttachments': [savedEntry('dog.png', '222')],
        'historyThreads': [
          jsonEncode({
            'board': 'g',
            'no': 5,
            'title': 'here',
            'at': DateTime(2026, 5).millisecondsSinceEpoch,
          }),
        ],
      }),
    );
    await a.sync.turnOn();
    sent.clear();
    calls.clear();

    Map<String, Object?> visit(int no, String title, DateTime at) => change(
      SyncKind.history,
      'g/$no',
      {'board': 'g', 'no': no, 'title': title, 'at': at.millisecondsSinceEpoch},
    );
    inbox.addAll([
      for (final Map<String, Object?> entry in [
        deletion(SyncKind.bookmark, 'g/2'),
        deletion(SyncKind.saved, '222'),
        // Visited earlier there than here: stays as it is here.
        visit(5, 'there', DateTime(2026, 4)),
        visit(6, 'newer', DateTime(2026, 6)),
        change(SyncKind.setting, 'allowNSFW', {'value': true}),
        // Not one this device takes from others.
        change(SyncKind.setting, 'videoCacheMegabytes', {'value': 1}),
      ])
        {...entry, 'seq': ++seq},
    ]);
    await a.sync.processInbox();
    await pumpEventQueue();

    expect(a.bookmarks.bookmarks, isEmpty);
    expect(a.saved.attachments, isEmpty);
    expect(File('${folders.media}/dog.png').existsSync(), isFalse);
    expect(a.history.threads.map((t) => t.title), ['newer', 'here']);
    expect(a.settings.allowNSFW.value, isTrue);
    expect(a.settings.videoCacheMegabytes.value, 300);
    expect(calls, isNot(contains('save')));
    expect(calls, isNot(contains('delete')));
    expect(inbox, isEmpty);
  });

  test('changes wait while the app is being rebuilt', () async {
    final SharedPreferences prefs = await prefsWith({});
    final a = await app(prefs);
    await a.sync.turnOn();
    a.bookmarks.dispose();

    inbox.add({
      ...change(SyncKind.bookmark, 'g/1', bookmark('g', 1)),
      'seq': ++seq,
    });
    await a.sync.processInbox();
    expect(inbox, hasLength(1));

    final BookmarksProvider bookmarks = BookmarksProvider(prefs, sync: a.sync);
    await pumpEventQueue();
    expect(bookmarks.bookmarks.map((b) => b.key), ['g/1']);
    expect(inbox, isEmpty);
  });

  test(
    "deleted from iCloud elsewhere, it turns off and keeps what's here",
    () async {
      final a = await app(
        await prefsWith({
          'favoriteThreads': [jsonEncode(bookmark('g', 2))],
        }),
      );
      await a.sync.turnOn();

      inbox.add({'event': 'zoneDeleted', 'seq': ++seq, 'deleted': false});
      await a.sync.processInbox();

      expect(a.sync.isOn, isFalse);
      expect(a.sync.notice, contains('deleted from iCloud'));
      expect(a.bookmarks.bookmarks.map((b) => b.key), ['g/2']);
      // Told once, and a dot on Settings until it's looked at.
      expect(a.sync.takeAlert()?.title, 'iCloud sync is off');
      expect(a.sync.takeAlert(), isNull);
      expect(a.sync.needsAttention, isTrue);
      a.sync.markNoticeSeen();
      expect(a.sync.needsAttention, isFalse);
    },
  );

  test(
    "a change iCloud refuses is told once, and marked until it's taken",
    () async {
      final a = await app(await prefsWith({}));
      await a.sync.turnOn();
      Future<void> swiftSays(Map<String, Object?> status) =>
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .handlePlatformMessage(
                channel.name,
                channel.codec.encodeMethodCall(MethodCall('status', status)),
                (_) {},
              );

      await swiftSays({
        'pending': 3,
        'pendingMedia': 2,
        'problem': 'failed',
        'error': 'Bad request (CloudKit error 12)',
      });
      expect(a.sync.status.pending, 3);
      expect(a.sync.status.pendingMedia, 2);
      expect(a.sync.needsAttention, isTrue);
      expect(a.sync.takeAlert()?.message, contains('CloudKit error 12'));
      // Still refused on the next send: not told again.
      await swiftSays({'pending': 3, 'problem': 'failed', 'error': 'Bad'});
      expect(a.sync.takeAlert(), isNull);

      await swiftSays({'pending': 0});
      expect(a.sync.needsAttention, isFalse);
      expect(a.sync.takeAlert(), isNull);
    },
  );

  test("Sync now fetches without waiting for what's going up", () async {
    final a = await app(await prefsWith({}));
    await a.sync.turnOn();
    calls.clear();
    sending = Completer<void>();

    bool done = false;
    final Future<void> syncing = a.sync.syncNow().then((_) => done = true);
    await pumpEventQueue();
    expect(calls, containsAll(<String>['send', 'fetch']));
    expect(done, isFalse);

    sending!.complete();
    await syncing;
    expect(done, isTrue);
  });

  test('turning off can delete what is in iCloud', () async {
    final a = await app(await prefsWith({}));
    await a.sync.turnOn();

    await a.sync.turnOff(deleteFromICloud: true);

    expect(a.sync.isOn, isFalse);
    expect(calls.last, 'stop');
  });

  test('a restored backup goes out as changes', () async {
    final SharedPreferences prefs = await prefsWith({
      'favoriteThreads': [
        jsonEncode(bookmark('g', 1)),
        jsonEncode(bookmark('g', 2)),
      ],
      'themeColor': 'cyan',
    });
    final a = await app(prefs);
    await a.sync.turnOn();
    sent.clear();
    final List<SyncItem> before = await a.sync.snapshot();

    await prefs.setStringList('favoriteThreads', [
      jsonEncode(bookmark('g', 2)),
      jsonEncode(bookmark('g', 3)),
    ]);
    await prefs.setString('themeColor', 'violet');
    await a.sync.pushChangesSince(before);

    expect(sentIds(), {
      syncId(SyncKind.bookmark, 'g/3'),
      syncId(SyncKind.setting, 'themeColor'),
    });
    expect(deleted, [syncId(SyncKind.bookmark, 'g/1')]);
  });

  test(
    "what's seen in a thread goes out when stored, and the newest wins",
    () async {
      final SharedPreferences prefs = await prefsWith({});
      final a = await app(prefs);
      await a.sync.turnOn();
      sent.clear();

      a.watched.noteThreadPosts(7, [7, 8, 9]);
      a.watched.noteThreadPosts(7, [7, 8, 9, 10, 11]);
      await pumpEventQueue();
      expect(sent, isEmpty);
      a.watched.dispose();
      await pumpEventQueue();
      expect(sentIds(), {syncId(SyncKind.threadMemory, '7')});

      final WatchedPostsProvider watched = WatchedPostsProvider(
        prefs,
        a.settings,
        sync: a.sync,
      );
      expect(watched.unseenPosts(7), {10, 11});
      Map<String, Object?> seen(Set<int> unseen, DateTime changedAt) =>
          change(SyncKind.threadMemory, '7', {
            'unseen': unseen.toList(),
            'lastRead': DateTime.now().toIso8601String(),
            'changedAt': changedAt.toIso8601String(),
          });
      inbox.add({
        ...seen({11}, DateTime.now().subtract(const Duration(days: 1))),
        'seq': ++seq,
      });
      await a.sync.processInbox();
      expect(watched.unseenPosts(7), {10, 11});

      inbox.add({
        ...seen(<int>{}, DateTime.now().add(const Duration(minutes: 1))),
        'seq': ++seq,
      });
      await a.sync.processInbox();
      expect(watched.unseenPosts(7), isEmpty);
      watched.dispose();
    },
  );

  test(
    'turning on waits until everything is there to take what comes in',
    () async {
      cloud = [change(SyncKind.bookmark, 'wsg/1', bookmark('wsg', 1))];
      final SharedPreferences prefs = await prefsWith({});
      final a = await app(prefs);
      a.bookmarks.dispose();

      final Future<void> turningOn = a.sync.turnOn();
      await pumpEventQueue();
      expect(calls, isNot(contains('fetch')));

      final BookmarksProvider bookmarks = BookmarksProvider(
        prefs,
        sync: a.sync,
      );
      await turningOn;
      expect(bookmarks.bookmarks.map((b) => b.key), ['wsg/1']);
      expect(a.sync.lastBroughtIn, 1);
      expect(sent, isEmpty);
    },
  );
}
