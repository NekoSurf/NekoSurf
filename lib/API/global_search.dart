import 'package:flutter/foundation.dart';
import 'package:flutter_chan/API/http_client.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart';

// 4chan has no search API: find.4chan.org only serves an HTML page, which
// is scraped here. If 4chan changes that page's markup, parsing finds
// nothing and the search page offers to open the site in the browser.

/// The find.4chan.org page for [query], optionally limited to [board].
Uri globalSearchUri(String query, {String? board, int offset = 0}) {
  return Uri.https('find.4chan.org', '/', {
    'q': query,
    if (board != null && board.isNotEmpty) 'b': board,
    if (offset > 0) 'o': '$offset',
  });
}

/// Thrown when find.4chan.org answers with something other than a results
/// page, such as an error or a Cloudflare challenge.
class GlobalSearchUnavailable implements Exception {
  const GlobalSearchUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'GlobalSearchUnavailable: $reason';
}

class GlobalSearchPage {
  const GlobalSearchPage({
    required this.posts,
    required this.totalHits,
    required this.nextOffset,
  });

  /// Matching posts, each with its `board` set. Replies have `resto` set to
  /// their thread; opening posts have `resto` 0.
  final List<Post> posts;

  /// Matches across all pages, when the page states it.
  final int? totalHits;

  /// Offset of the next page, or null on the last one.
  final int? nextOffset;
}

Future<GlobalSearchPage> searchAll4chan(
  String query, {
  String? board,
  int offset = 0,
}) async {
  final Response response = await httpClient.get(
    globalSearchUri(query, board: board, offset: offset),
  );

  if (response.statusCode != 200) {
    throw GlobalSearchUnavailable('HTTP ${response.statusCode}');
  }

  final GlobalSearchPage? page = await compute(_parseSearchPage, (
    body: response.body,
    offset: offset,
  ));
  if (page == null) {
    throw const GlobalSearchUnavailable('Unrecognized response');
  }
  return page;
}

final RegExp _postLink = RegExp(
  r'boards\.4chan(?:nel)?\.org/(\w+)/thread/(\d+)[^#"]*#p(\d+)',
);
final RegExp _fileLink = RegExp(r'i\.4cdn\.org/\w+/(\d+)(\.\w+)$');
final RegExp _offsetLink = RegExp(r'[?&]o=(\d+)');
final RegExp _hitCount = RegExp(r'(\d[\d,]*) (?:comments?|results?)');

/// Null when [body] isn't a results page at all, so a changed or blocked
/// page isn't mistaken for "no results".
@visibleForTesting
GlobalSearchPage? parseGlobalSearchPage(String body, {int offset = 0}) =>
    _parseSearchPage((body: body, offset: offset));

GlobalSearchPage? _parseSearchPage(({String body, int offset}) input) {
  final Document document = html_parser.parse(input.body);

  final List<Element> containers = document.querySelectorAll('.postContainer');
  final List<Post> posts = <Post>[
    for (final Element container in containers) ?_parsePost(container),
  ];

  final Match? hits = _hitCount.firstMatch(document.body?.text ?? '');

  // Every results page, even an empty one, carries the search form or a
  // hit count.
  if (posts.isEmpty &&
      hits == null &&
      document.querySelector('input[name="q"]') == null) {
    return null;
  }

  int? nextOffset;
  for (final Element link in document.querySelectorAll('a[href]')) {
    final Match? match = _offsetLink.firstMatch(link.attributes['href']!);
    final int? linked = match == null ? null : int.tryParse(match.group(1)!);
    if (linked != null &&
        linked > input.offset &&
        (nextOffset == null || linked < nextOffset)) {
      nextOffset = linked;
    }
  }

  return GlobalSearchPage(
    posts: posts,
    totalHits: hits == null
        ? null
        : int.tryParse(hits.group(1)!.replaceAll(',', '')),
    nextOffset: posts.isEmpty ? null : nextOffset,
  );
}

Post? _parsePost(Element container) {
  // Board and numbers come from the post's own permalink, not from links
  // quoted in its comment.
  Match? link;
  for (final Element a in container.querySelectorAll('a[href]')) {
    if (_isInComment(a)) {
      continue;
    }
    link = _postLink.firstMatch(a.attributes['href']!);
    if (link != null) {
      break;
    }
  }
  if (link == null) {
    return null;
  }

  final int thread = int.parse(link.group(2)!);
  final int no = int.parse(link.group(3)!);

  String? text(String selector) {
    for (final Element element in container.querySelectorAll(selector)) {
      final String value = element.text.trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  final String? utc = container
      .querySelector('[data-utc]')
      ?.attributes['data-utc'];

  final Match? file = _fileLink.firstMatch(
    container.querySelector('a.fileThumb')?.attributes['href'] ?? '',
  );

  return Post(
    no: no,
    resto: no == thread ? 0 : thread,
    board: link.group(1),
    sub: text('.subject'),
    name: text('.name'),
    com: container.querySelector('.postMessage')?.innerHtml,
    time: utc == null ? null : int.tryParse(utc),
    tim: file == null ? null : int.parse(file.group(1)!),
    ext: file?.group(2),
  );
}

bool _isInComment(Element element) {
  for (Element? e = element.parent; e != null; e = e.parent) {
    if (e.classes.contains('postMessage')) {
      return true;
    }
  }
  return false;
}
