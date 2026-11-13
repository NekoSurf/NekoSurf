import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_chan/board/favorite_model.dart';
import 'package:flutter_chan/bookmarks/bookmark.dart';
import 'package:flutter_chan/bookmarks/bookmarks_model.dart';
import 'package:flutter_chan/history/history_model.dart';
import 'package:flutter_chan/history/watched_posts_model.dart';
import 'package:flutter_chan/saved/saved_attachment.dart';
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
  late List<String> downloadsAsked;
  // What iCloud has, by record id; null as if it had no zone.
  List<String>? cloudIds;
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
    downloadsAsked = [];
    cloudIds = null;
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
            case 'download':
              downloadsAsked.addAll((call.arguments as List).cast());
              return null;
            case 'cloudIds':
              return cloudIds;
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
      change(SyncKind.bookmark, 'wsg/1', {...bookmark('wsg', 1), 'addedAt': 1}),
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
    // Of an older post, iCloud's comes first, as on the other device.
    expect(a.saved.attachments.map((s) => s.fileName), [
      'cat (2).png',
      'cat.png',
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

      await swiftSays({
        'pending': 1,
        'pendingMedia': 1,
        'syncing': true,
        'uploadProgress': 0.42,
        'uploadBytes': 1900000,
        'uploadKey': '111',
        'pendingFileKeys': ['111', '222'],
      });
      expect(a.sync.status.uploadProgress, 0.42);
      expect(a.sync.status.uploadBytes, 1900000);
      // On the Saved tab: going up, waiting its turn, in iCloud.
      expect(a.sync.fileUpload('111')?.progress, 0.42);
      expect(a.sync.fileUpload('222'), isNotNull);
      expect(a.sync.fileUpload('222')?.progress, isNull);
      expect(a.sync.fileUpload('333'), isNull);
      // Several at once, once the app's left.
      await swiftSays({
        'pending': 2,
        'pendingMedia': 2,
        'uploadKey': '111',
        'uploadProgress': 0.5,
        'uploadProgresses': {'111': 0.5, '222': 0.25},
        'pendingFileKeys': ['111', '222'],
      });
      expect(a.sync.fileUpload('111')?.progress, 0.5);
      expect(a.sync.fileUpload('222')?.progress, 0.25);

      await swiftSays({'pending': 0});
      expect(a.sync.status.uploadProgress, isNull);
      expect(a.sync.fileUpload('111'), isNull);
      expect(a.sync.needsAttention, isFalse);
      expect(a.sync.takeAlert(), isNull);
    },
  );

  test('a saved file from another device shows up at once, as a '
      'placeholder till its file comes down', () async {
    final a = await app(await prefsWith({}));
    await a.sync.turnOn();
    final File thumbnail = File('${dir.path}/incoming-thumb')
      ..writeAsStringSync('a frame');
    Map<String, Object?> dog({int? fileBytes}) => {
      ...change(SyncKind.saved, '333', {
        'savedAttachmentType': 'video',
        'fileName': 'dog.mp4',
        'thumbnail': 'dog.jpg',
        'id': '333',
      }),
      'thumbnail': thumbnail.existsSync() ? thumbnail.path : null,
      'fileBytes': fileBytes,
      'seq': ++seq,
    };

    // Still going up from the phone it was saved on.
    inbox.add(dog());
    await a.sync.processInbox();
    final SavedAttachment placeholder = a.saved.attachments.single;
    expect(a.saved.hasFile(placeholder), isFalse);
    expect(a.saved.isInICloud(placeholder), isFalse);
    expect(a.saved.contains('333'), isTrue);
    expect(
      File(folders.thumbnailPath(placeholder)).readAsStringSync(),
      'a frame',
    );
    // Asked for anyway: it comes down if it's up already.
    await pumpEventQueue();
    expect(downloadsAsked, [syncId(SyncKind.saved, '333')]);
    // Its file isn't missing, so it isn't taken out, nor deleted in iCloud.
    await a.saved.reconcileWithDisk(folders);
    expect(a.saved.attachments, hasLength(1));
    await pumpEventQueue();
    expect(deleted, isEmpty);

    // Its phone went on uploading after it was left: iCloud tells of a
    // file going up, before its record says so.
    downloadsAsked.clear();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(const MethodCall('filesChanged')),
          (_) {},
        );
    await pumpEventQueue();
    expect(downloadsAsked, [syncId(SyncKind.saved, '333')]);

    // Its record says it's up.
    downloadsAsked.clear();
    inbox.add(dog(fileBytes: 4));
    await a.sync.processInbox();
    await pumpEventQueue();
    expect(a.saved.isInICloud(a.saved.attachments.single), isTrue);
    expect(downloadsAsked, [syncId(SyncKind.saved, '333')]);

    // Asked for again on the next launch.
    downloadsAsked.clear();
    final again = await app(await SharedPreferences.getInstance());
    await pumpEventQueue();
    expect(again.saved.hasFile(again.saved.attachments.single), isFalse);
    expect(downloadsAsked, [syncId(SyncKind.saved, '333')]);

    final File media = File('${dir.path}/incoming-dog')
      ..writeAsStringSync('woof');
    inbox.add({
      'id': syncId(SyncKind.saved, '333'),
      'kind': 'saved',
      'media': media.path,
      'fileOnly': true,
      'deleted': false,
      'seq': ++seq,
    });
    await a.sync.processInbox();
    expect(a.saved.hasFile(a.saved.attachments.single), isTrue);
    expect(File('${folders.media}/dog.mp4').readAsStringSync(), 'woof');
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SavedAttachmentsProvider.placeholdersKey), '{}');
  });

  test(
    "a saved file that's here takes when it was saved from elsewhere",
    () async {
      File('${folders.media}/a.png').writeAsStringSync('a');
      File('${folders.media}/b.png').writeAsStringSync('b');
      final a = await app(
        await prefsWith({
          'savedAttachments': [
            jsonEncode({...jsonDecode(savedEntry('a.png', '100')) as Map}),
            jsonEncode({...jsonDecode(savedEntry('b.png', '200')) as Map}),
          ],
        }),
      );
      await a.sync.turnOn();
      // Saved again on another device, after b.
      inbox.add({
        ...change(SyncKind.saved, '100', {
          ...jsonDecode(savedEntry('a.png', '100')) as Map<String, Object?>,
          'addedAt': 1800000000000,
        }),
        'seq': ++seq,
      });
      await a.sync.processInbox();

      expect(a.saved.attachments.map((s) => s.id), ['200', '100']);
      expect(a.saved.attachments.last.addedAt, 1800000000000);
      expect(a.saved.hasFile(a.saved.attachments.last), isTrue);
    },
  );

  test("a saved file that's here goes by iCloud's order when iCloud has no "
      'save time for it', () async {
    File('${folders.media}/a.png').writeAsStringSync('a');
    File('${folders.media}/b.png').writeAsStringSync('b');
    final a = await app(
      await prefsWith({
        'savedAttachments': [
          jsonEncode({...jsonDecode(savedEntry('b.png', '200')) as Map}),
          jsonEncode({
            ...jsonDecode(savedEntry('a.png', '100')) as Map,
            'addedAt': 1800000000000,
          }),
        ],
      }),
    );
    await a.sync.turnOn();
    // Sent from a device that has it from before save times were kept.
    inbox.add({
      ...change(
        SyncKind.saved,
        '100',
        jsonDecode(savedEntry('a.png', '100')) as Map<String, Object?>,
      ),
      'seq': ++seq,
    });
    await a.sync.processInbox();

    expect(a.saved.attachments.map((s) => s.id), ['100', '200']);
    expect(a.saved.attachments.first.addedAt, isNull);
    expect(a.saved.hasFile(a.saved.attachments.first), isTrue);
  });

  test('how a saved file from another device is coming down', () async {
    final a = await app(await prefsWith({}));
    await a.sync.turnOn();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(
            MethodCall('status', {
              'downloadId': syncId(SyncKind.saved, '111'),
              'downloadProgress': 0.3,
              'downloadIds': [syncId(SyncKind.saved, '222')],
            }),
          ),
          (_) {},
        );

    expect(a.sync.fileDownload('111')?.progress, 0.3);
    expect(a.sync.fileDownload('222'), isNotNull);
    expect(a.sync.fileDownload('222')?.progress, isNull);
    expect(a.sync.fileDownload('333'), isNull);
  });

  test('bookmarks are in the same order on every device', () async {
    final a = await app(
      await prefsWith({
        'sync.iCloud': true,
        'sync.joined': true,
        // From before when they were bookmarked was kept.
        'favoriteThreads': [
          jsonEncode(bookmark('g', 5)),
          jsonEncode(bookmark('g', 1)),
        ],
      }),
    );
    a.bookmarks.setNewestFirst(false);
    await pumpEventQueue();

    // Numbered in this phone's order, and sent, for the others to take.
    expect(a.bookmarks.bookmarks.map((b) => b.key), ['g/5', 'g/1']);
    expect(sent.map((s) => jsonDecode(s['data']! as String)['addedAt']), [
      1,
      2,
    ]);

    // Another device's numbers win once they come; new ones go last.
    inbox.add({
      ...change(SyncKind.bookmark, 'g/1', {...bookmark('g', 1), 'addedAt': 1}),
      'seq': ++seq,
    });
    inbox.add({
      ...change(SyncKind.bookmark, 'g/5', {...bookmark('g', 5), 'addedAt': 2}),
      'seq': ++seq,
    });
    await a.sync.processInbox();
    await a.bookmarks.addBookmark(Bookmark(board: 'g', no: 3));
    expect(a.bookmarks.bookmarks.map((b) => b.key), ['g/1', 'g/5', 'g/3']);
  });

  test('a bookmark from iCloud that says not when it was made is sent back '
      'with a time, for every device to put it in the same place', () async {
    final a = await app(
      await prefsWith({'sync.iCloud': true, 'sync.joined': true}),
    );
    await pumpEventQueue();
    sent.clear();

    // From an older NekoSurf, which didn't keep when.
    inbox.add({
      ...change(SyncKind.bookmark, 'g/1', bookmark('g', 1)),
      'seq': ++seq,
    });
    await a.sync.processInbox();
    await pumpEventQueue();

    final int? addedAt = a.bookmarks.bookmarks.single.addedAt;
    expect(addedAt, isNotNull);
    expect(sentIds(), {syncId(SyncKind.bookmark, 'g/1')});
    expect(jsonDecode(sent.single['data']! as String)['addedAt'], addedAt);
  });

  test("Sync now sends what iCloud doesn't have, but not what was deleted "
      'elsewhere', () async {
    String stored(int no) => jsonEncode({...bookmark('g', no), 'addedAt': no});
    final a = await app(
      await prefsWith({
        'favoriteThreads': [stored(1), stored(2), stored(3)],
      }),
    );
    await a.sync.turnOn();
    sent.clear();
    // iCloud has g/1; g/2 was deleted on another device, g/3 lost there.
    cloudIds = [syncId(SyncKind.bookmark, 'g/1')];
    cloud = [deletion(SyncKind.bookmark, 'g/2')];

    await a.sync.syncNow();
    await pumpEventQueue();

    expect(a.bookmarks.bookmarks.map((b) => b.key), isNot(contains('g/2')));
    expect(sentIds(), {syncId(SyncKind.bookmark, 'g/3')});
  });

  test('once after updating, what iCloud lost goes up again', () async {
    cloudIds = <String>[];
    final SharedPreferences prefs = await prefsWith({
      'sync.iCloud': true,
      'sync.joined': true,
      'favoriteThreads': [
        jsonEncode({...bookmark('g', 1), 'addedAt': 1}),
      ],
    });
    await app(prefs);
    await pumpEventQueue();
    expect(sentIds(), {syncId(SyncKind.bookmark, 'g/1')});
    expect(prefs.getBool('sync.checkedICloud'), isTrue);

    // Not again.
    sent.clear();
    await app(prefs);
    await pumpEventQueue();
    expect(sent, isEmpty);
  });

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
        jsonEncode({...bookmark('g', 1), 'addedAt': 1}),
        jsonEncode({...bookmark('g', 2), 'addedAt': 2}),
      ],
      'themeColor': 'cyan',
    });
    final a = await app(prefs);
    await a.sync.turnOn();
    sent.clear();
    final List<SyncItem> before = await a.sync.snapshot();

    await prefs.setStringList('favoriteThreads', [
      jsonEncode({...bookmark('g', 2), 'addedAt': 2}),
      jsonEncode({...bookmark('g', 3), 'addedAt': 3}),
    ]);
    await prefs.setString('themeColor', 'violet');
    await a.sync.pushChangesSince(before);

    expect(sentIds(), {
      syncId(SyncKind.bookmark, 'g/3'),
      syncId(SyncKind.setting, 'themeColor'),
    });
    expect(deleted, [syncId(SyncKind.bookmark, 'g/1')]);
  });

  test('a setting goes out with when it was changed, so a newer one '
      'elsewhere wins over it', () async {
    final SharedPreferences prefs = await prefsWith({
      'themeColor': 'cyan',
      'allowNSFW': true,
    });
    final a = await app(prefs);
    await a.sync.turnOn();
    sent.clear();

    final DateTime before = DateTime.now();
    await a.settings.themeColor.set(ThemeColor.violet);
    await pumpEventQueue();
    final int changed = sent.single['modifiedAt']! as int;
    expect(changed, greaterThanOrEqualTo(before.millisecondsSinceEpoch));

    // Sent again from what's stored, as when the sync engine starts over:
    // as changed then, and one never changed as long ago.
    final Map<String, SyncItem> stored = {
      for (final SyncItem item in await a.sync.snapshot()) item.key: item,
    };
    expect(stored['themeColor']!.modifiedAt.millisecondsSinceEpoch, changed);
    expect(stored['allowNSFW']!.modifiedAt.millisecondsSinceEpoch, 0);

    // One from elsewhere keeps its time here.
    inbox.add({
      ...change(SyncKind.setting, 'allowNSFW', {'value': false}),
      'modifiedAt': 1800000000000,
      'seq': ++seq,
    });
    await a.sync.processInbox();
    expect(a.settings.allowNSFW.value, isFalse);
    expect(
      SettingsProvider.changedAt(prefs, 'allowNSFW')?.millisecondsSinceEpoch,
      1800000000000,
    );
  });

  test('what changes in a thread goes out at most every so often while '
      "it's read, and at once when it's left", () async {
    final SharedPreferences prefs = await prefsWith({});
    final a = await app(prefs);
    await a.sync.turnOn();
    a.watched.dispose();
    final WatchedPostsProvider watched = WatchedPostsProvider(
      prefs,
      a.settings,
      sync: a.sync,
      saveDelay: const Duration(milliseconds: 10),
      syncInterval: const Duration(milliseconds: 400),
    );
    sent.clear();
    int sends() =>
        sent.where((s) => s['id'] == syncId(SyncKind.threadMemory, '7')).length;

    // The first goes once it's stored.
    watched.noteThreadPosts(7, [7, 8, 9]);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(sends(), 1);

    // Those soon after wait, and go together.
    watched.markPostsSeen(7, [8]);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    watched.markPostsSeen(7, [9]);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(sends(), 1);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(sends(), 2);

    // Leaving it doesn't wait.
    watched.noteThreadPosts(7, [7, 8, 9, 10]);
    watched.leftThread();
    await pumpEventQueue();
    expect(sends(), 3);
    watched.dispose();
  });

  test(
    "what's seen in a thread goes out when stored, and the newest wins",
    () async {
      final SharedPreferences prefs = await prefsWith({});
      final a = await app(prefs);
      await a.sync.turnOn();
      sent.clear();

      a.watched.noteThreadPosts(7, [7, 8, 9]);
      a.watched.markPostsSeen(7, [8, 9]);
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
      cloud = [
        change(SyncKind.bookmark, 'wsg/1', {
          ...bookmark('wsg', 1),
          'addedAt': 1,
        }),
      ];
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
