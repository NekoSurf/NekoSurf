import 'package:flutter_chan/saved/saved_browsing.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the sort order is kept for next time', () async {
    SharedPreferences.setMockInitialValues({});
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final SavedBrowsing first = SavedBrowsing(SettingsProvider(prefs));
    expect(first.newestFirst, isTrue);
    first.setNewestFirst(false);

    final SavedBrowsing next = SavedBrowsing(SettingsProvider(prefs));
    expect(next.newestFirst, isFalse);
  });
}
