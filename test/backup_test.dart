import 'dart:convert';
import 'dart:io';

import 'package:flutter_chan/saved/saved_attachment.dart';
import 'package:flutter_chan/saved/saved_folders.dart';
import 'package:flutter_chan/settings/backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('backup_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// The saved files of an install, in folders of their own under [name].
  SavedFolders foldersOf(String name) {
    final SavedFolders folders = SavedFolders(
      media: '${dir.path}/$name/media',
      thumbnails: '${dir.path}/$name/thumbs',
    );
    Directory(folders.media).createSync(recursive: true);
    Directory(folders.thumbnails).createSync(recursive: true);
    return folders;
  }

  String video(String fileName, String id) => jsonEncode({
    'savedAttachmentType': 'video',
    'fileName': fileName,
    'thumbnail': '$id.jpg',
    'id': id,
  });

  String image(String fileName, String id) => jsonEncode({
    'savedAttachmentType': 'image',
    'fileName': fileName,
    'thumbnail': fileName,
    'id': id,
  });

  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  List<String> savedNames(SharedPreferences prefs) => [
    for (final String entry in prefs.getStringList('savedAttachments')!)
      SavedAttachment.fromStored(entry)!.fileName,
  ];

  test('a zip brings everything back on a fresh install', () async {
    final SavedFolders phone = foldersOf('phone');
    File('${phone.media}/cat.webm').writeAsStringSync('meow');
    File('${phone.thumbnails}/111.jpg').writeAsStringSync('thumb');
    File('${phone.media}/dog.png').writeAsStringSync('woof');
    final SharedPreferences prefs = await prefsWith({
      'savedAttachments': [video('cat.webm', '111'), image('dog.png', '222')],
      'favoriteThreads': ['{"board":"wsg","no":1}'],
      'allowNSFW': true,
      'videoCacheMegabytes': 500,
      'someRatio': 0.5,
      'themeColor': 'violet',
      'sync.iCloud': true,
    });
    final File zip = await createBackupFile(
      prefs,
      phone,
      dir,
      now: DateTime(2026, 11, 11),
    );
    expect(zip.path, endsWith('NekoSurf Backup 2026-11-11.zip'));

    final SavedFolders fresh = foldersOf('fresh');
    final SharedPreferences restored = await prefsWith({
      'sync.iCloud': false,
      'themeColor': 'cyan',
      'trackHistory': false,
    });
    await restoreBackupFile(zip.path, restored, fresh, dir);

    expect(savedNames(restored), ['cat.webm', 'dog.png']);
    expect(File('${fresh.media}/cat.webm').readAsStringSync(), 'meow');
    expect(File('${fresh.thumbnails}/111.jpg').readAsStringSync(), 'thumb');
    expect(File('${fresh.media}/dog.png').readAsStringSync(), 'woof');
    expect(restored.getStringList('favoriteThreads'), [
      '{"board":"wsg","no":1}',
    ]);
    expect(restored.getBool('allowNSFW'), isTrue);
    expect(restored.getInt('videoCacheMegabytes'), 500);
    expect(restored.getDouble('someRatio'), 0.5);
    expect(restored.getString('themeColor'), 'violet');
    // What the backup didn't have goes back to its default.
    expect(restored.containsKey('trackHistory'), isFalse);
    // This install's own preferences stay.
    expect(restored.getBool('sync.iCloud'), isFalse);
  });

  test('restoring adds to what is saved, renaming a taken name', () async {
    final SavedFolders phone = foldersOf('phone');
    File('${phone.media}/cat.webm').writeAsStringSync('old cat');
    File('${phone.media}/same.png').writeAsStringSync('same');
    final SharedPreferences before = await prefsWith({
      'savedAttachments': [image('cat.webm', '111'), image('same.png', '3')],
    });
    final File zip = await createBackupFile(before, phone, dir);

    final SavedFolders now = foldersOf('now');
    File('${now.media}/cat.webm').writeAsStringSync('new cat');
    File('${now.media}/same.png').writeAsStringSync('same here');
    final SharedPreferences prefs = await prefsWith({
      'savedAttachments': [image('cat.webm', '999'), image('same.png', '3')],
    });
    await restoreBackupFile(zip.path, prefs, now, dir);

    // The backup's (older) first; one saved here already isn't doubled.
    expect(savedNames(prefs), ['cat (2).webm', 'cat.webm', 'same.png']);
    expect(File('${now.media}/cat (2).webm').readAsStringSync(), 'old cat');
    expect(File('${now.media}/cat.webm').readAsStringSync(), 'new cat');
    expect(File('${now.media}/same.png').readAsStringSync(), 'same here');
  });

  test('a file that is not a backup changes nothing', () async {
    final File notZip = File('${dir.path}/photo.zip')..writeAsStringSync('no');
    final SavedFolders phone = foldersOf('phone');
    final SharedPreferences prefs = await prefsWith({'allowNSFW': true});

    await expectLater(
      restoreBackupFile(notZip.path, prefs, phone, dir),
      throwsA(isA<NotABackup>()),
    );
    await expectLater(
      restoreBackupFolder(Directory('${dir.path}/empty'), prefs, phone),
      throwsA(isA<NotABackup>()),
    );
    expect(prefs.getBool('allowNSFW'), isTrue);
  });

  test('a backup from a newer NekoSurf is refused', () async {
    final Directory newer = Directory('${dir.path}/newer')..createSync();
    File(
      '${newer.path}/backup.json',
    ).writeAsStringSync('{"format": 99, "preferences": {}}');
    final SharedPreferences prefs = await prefsWith({'allowNSFW': true});

    await expectLater(
      restoreBackupFolder(newer, prefs, foldersOf('phone')),
      throwsA(isA<NotABackup>().having((e) => e.newer, 'newer', isTrue)),
    );
    expect(prefs.getBool('allowNSFW'), isTrue);
  });
}
