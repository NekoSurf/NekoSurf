import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_chan/saved/saved_attachment.dart';
import 'package:flutter_chan/saved/saved_attachments_model.dart';
import 'package:flutter_chan/saved/saved_folders.dart';
import 'package:flutter_chan/saved/saved_media_viewer_page.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late SavedFolders folders;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('saved_attachments_test');
    folders = SavedFolders(
      media: Directory('${dir.path}/media').absolute.path,
      thumbnails: Directory('${dir.path}/thumbs').absolute.path,
    );
    Directory(folders.media).createSync();
    Directory(folders.thumbnails).createSync();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  String stored(String fileName, {String? id}) => jsonEncode({
    'savedAttachmentType': 'image',
    'fileName': fileName,
    'thumbnail': fileName,
    'id': id ?? fileName,
  });

  Future<SavedAttachmentsProvider> provider(List<String> entries) async {
    SharedPreferences.setMockInitialValues({'savedAttachments': entries});
    return SavedAttachmentsProvider(await SharedPreferences.getInstance());
  }

  test('reads what older versions stored', () async {
    final SavedAttachmentsProvider saved = await provider([
      '123.webm',
      '{"savedAttachmentType":1,"fileName":"folder/456.jpg"}',
      'not json {',
      '{broken',
    ]);

    final Map<String, SavedAttachment> all = {
      for (final SavedAttachment a in saved.attachments) a.id: a,
    };
    expect(all.keys, unorderedEquals(['123', '456', 'not json {']));
    expect(all['123']!.isVideo, isTrue);
    expect(all['123']!.thumbnail, '123.jpg');
    expect(all['456']!.fileName, '456.jpg');
    expect(all['456']!.isVideo, isTrue);
  });

  test('lists what was saved by when, the same on every device', () async {
    final SavedAttachmentsProvider saved = await provider([
      jsonEncode({
        ...jsonDecode(stored('new.jpg', id: '1500000000000')) as Map,
        'addedAt': 1800000000000,
      }),
      // From before when it was saved was kept: when its post was made,
      // its upload's tim, in milliseconds or microseconds.
      stored('older.jpg', id: '1700000000000000'),
      stored('oldest.jpg', id: '1600000000000'),
    ]);

    expect(saved.attachments.map((a) => a.fileName), [
      'oldest.jpg',
      'older.jpg',
      'new.jpg',
    ]);
  });

  test('drops entries whose file was deleted outside the app', () async {
    File(folders.pathOfFile('kept.jpg')).writeAsStringSync('x');
    final SavedAttachmentsProvider saved = await provider([
      stored('kept.jpg'),
      stored('gone.jpg'),
    ]);

    await saved.reconcileWithDisk(folders);

    expect(saved.attachments.map((a) => a.fileName), ['kept.jpg']);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('savedAttachments'), hasLength(1));
  });

  test(
    'brings back a file left in the folder they were moved out of',
    () async {
      final String other = Directory('${dir.path}/other').absolute.path;
      Directory(other).createSync();
      // Written there by a download that started before the move.
      File('$other/late.jpg').writeAsStringSync('late');
      final SavedFolders withOther = SavedFolders(
        media: folders.media,
        thumbnails: folders.thumbnails,
        elsewhere: other,
      );
      final SavedAttachmentsProvider saved = await provider([
        stored('late.jpg'),
        stored('gone.jpg'),
      ]);

      await saved.reconcileWithDisk(withOther);

      expect(saved.attachments.map((a) => a.fileName), ['late.jpg']);
      expect(File(withOther.pathOfFile('late.jpg')).readAsStringSync(), 'late');
      expect(File('$other/late.jpg').existsSync(), isFalse);
    },
  );

  test("gives files named after their upload the uploader's name", () async {
    File(folders.pathOfFile('123.jpg')).writeAsStringSync('x');
    final SavedAttachmentsProvider saved = await provider([
      jsonEncode({
        'savedAttachmentType': 'image',
        'fileName': '123.jpg',
        'thumbnail': '123.jpg',
        'originalName': 'cat.jpg',
      }),
    ]);

    await saved.reconcileWithDisk(folders);

    final SavedAttachment renamed = saved.attachments.single;
    expect(renamed.fileName, 'cat.jpg');
    expect(renamed.thumbnail, 'cat.jpg');
    expect(renamed.id, '123');
    expect(File(folders.pathOfFile('cat.jpg')).existsSync(), isTrue);
  });

  testWidgets(
    "the viewer calls a file what it's called, not the poster's name",
    (tester) async {
      final SavedAttachment attachment = SavedAttachment.fromStored(
        jsonEncode({
          'savedAttachmentType': 'image',
          'fileName': '1700000000000.jpg',
          'thumbnail': '1700000000000.jpg',
          'originalName': 'my_cool_image.jpg',
          'id': '1700000000000',
        }),
      )!;
      SharedPreferences.setMockInitialValues({});
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(
              value: SettingsProvider(prefs),
            ),
            ChangeNotifierProvider<SavedAttachmentsProvider>.value(
              value: SavedAttachmentsProvider(prefs),
            ),
          ],
          child: MaterialApp(
            home: SavedMediaViewerPage(
              attachments: [attachment],
              initialIndex: 0,
              folders: folders,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('1700000000000.jpg'), findsOneWidget);
      expect(find.text('my_cool_image.jpg'), findsNothing);
    },
  );
}
