import 'package:flutter/material.dart';
import 'package:flutter_chan/chan/http_client.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/saved/saved_attachments_model.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/thread/thread_media_viewer_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hears how the viewer asks to save a file, without saving it.
class _FakeSaved extends SavedAttachmentsProvider {
  _FakeSaved(super.prefs);

  Post? post;
  String? fileName;

  @override
  Future<void> save(Post post, {required String fileName}) async {
    this.post = post;
    this.fileName = fileName;
  }
}

void main() {
  late SharedPreferences prefs;

  setUpAll(() {
    http.runWithClient(
      () => httpClient,
      () => MockClient((_) async => http.Response('', 404)),
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('the setting is off until turned on, and stays on', () async {
    final SettingsProvider settings = SettingsProvider(prefs);
    expect(settings.serverFileNames.value, isFalse);

    await settings.serverFileNames.set(true);
    expect(SettingsProvider(prefs).serverFileNames.value, isTrue);
  });

  Future<_FakeSaved> tapSave(WidgetTester tester, {required bool on}) async {
    final SettingsProvider settings = SettingsProvider(prefs);
    await settings.serverFileNames.set(on);
    final _FakeSaved saved = _FakeSaved(prefs);
    final ValueNotifier<int?> current = ValueNotifier<int?>(1);
    addTearDown(current.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<SavedAttachmentsProvider>.value(value: saved),
        ],
        child: MaterialApp(
          home: ThreadMediaViewerPage(
            mediaPosts: [
              Post(
                board: 'g',
                no: 1,
                tim: 1700000000000,
                ext: '.jpg',
                filename: 'my_cool_image',
              ),
            ],
            initialIndex: 0,
            currentPost: current,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Save'));
    await tester.pump();
    return saved;
  }

  testWidgets("with it off, a save takes the poster's name", (tester) async {
    final _FakeSaved saved = await tapSave(tester, on: false);

    expect(saved.fileName, 'my_cool_image.jpg');
  });

  testWidgets("with it on, a save takes 4chan's name", (tester) async {
    final _FakeSaved saved = await tapSave(tester, on: true);

    expect(saved.fileName, '1700000000000.jpg');
  });
}
