import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
