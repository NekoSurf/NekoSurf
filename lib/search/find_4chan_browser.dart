import 'package:flutter_chan/chan/urls.dart' as urls;
import 'package:flutter_chan/search/global_search.dart';
import 'package:flutter_chan/ui/checked_browser.dart';

/// Loads find.4chan.org in a web view, past its Cloudflare check, and reads
/// the results out of it.
class Find4chanBrowser extends CheckedBrowser {
  Future<GlobalSearchPage> search(String query, {int offset = 0}) async {
    try {
      return await load(
        urls.find(query: query, offset: offset),
        (String html) =>
            parseGlobalSearchPageInBackground(html, offset: offset),
      );
    } on CheckedBrowserFailed catch (e) {
      throw GlobalSearchUnavailable(e.reason);
    }
  }
}
