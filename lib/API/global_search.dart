import 'package:flutter/foundation.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

// 4chan has no search API: find.4chan.org only serves an HTML page, behind
// Cloudflare. Find4chanBrowser loads it in a web view, which can pass the
// Cloudflare check, and the page is parsed here. If 4chan changes that
// page's markup, parsing fails and the search page offers to open the site
// in the browser.

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

/// [parseGlobalSearchPage] off the UI isolate.
Future<GlobalSearchPage?> parseGlobalSearchPageInBackground(
  String body, {
  int offset = 0,
}) {
  return compute(_parseSearchPage, (body: body, offset: offset));
}

/// Whether [body] is Cloudflare's "checking your browser" page rather than
/// find.4chan.org itself.
bool isCloudflareChallenge(String body) {
  final String lower = body.toLowerCase();
  return lower.contains('challenges.cloudflare.com') ||
      lower.contains('cf-chl') ||
      lower.contains('challenge-platform') ||
      lower.contains('<title>just a moment');
}

final RegExp _postLink = RegExp(
  r'boards\.4chan(?:nel)?\.org/(\w+)/thread/(\d+)(?:[^#"\s]*#p(\d+))?',
);
// File names are the upload time in ms (tim), plus "s" for thumbnails.
final RegExp _fileName = RegExp(r'/(\d{10,})(s?)\.(\w+)(?:$|[?#])');
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
  final bool isOp =
      container.classes.contains('opContainer') ||
      container.querySelector('.post.op') != null;

  // 4chan's markup numbers every post in its ids (pc123, p123, m123); that
  // beats links, which can also point at the thread's opening post.
  final int? idNo = _idNumber(container);

  // Board and thread come from a link to the thread, outside the comment
  // so quoted posts don't count. The post's own permalink is preferred.
  Match? link;
  for (final Element a in container.querySelectorAll('a[href]')) {
    if (_isInComment(a)) {
      continue;
    }
    final Match? match = _postLink.firstMatch(a.attributes['href']!);
    if (match == null) {
      continue;
    }
    final int? linked = int.tryParse(match.group(3) ?? '');
    if (idNo == null ? linked != null : linked == idNo) {
      link = match;
      break;
    }
    link ??= match;
  }
  if (link == null) {
    return null;
  }

  final int thread = int.parse(link.group(2)!);
  final int? no =
      idNo ?? int.tryParse(link.group(3) ?? '') ?? (isOp ? thread : null);
  if (no == null) {
    return null;
  }

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

  // The thumbnail's <img> is the surest source; the link around it may
  // point at the full file or at the thread.
  final Element? thumb =
      container.querySelector('.fileThumb') ?? container.querySelector('.file');
  final Element? img = thumb?.querySelector('img');
  int? tim;
  String? ext;
  for (final String? url in [
    thumb?.attributes['href'],
    img?.attributes['src'],
    img?.attributes['data-src'],
  ]) {
    final Match? file = url == null ? null : _fileName.firstMatch(url);
    if (file == null) {
      continue;
    }
    tim ??= int.parse(file.group(1)!);
    if (file.group(2)!.isEmpty) {
      ext ??= '.${file.group(3)}';
    }
  }

  return Post(
    no: no,
    resto: no == thread ? 0 : thread,
    board: link.group(1),
    sub: text('.subject'),
    name: text('.name'),
    com: container.querySelector('.postMessage')?.innerHtml,
    time: utc == null ? null : int.tryParse(utc),
    tim: tim,
    ext: ext,
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

final RegExp _postId = RegExp(r'^(?:pc|p|m)(\d+)$');

int? _idNumber(Element container) {
  for (final Element? element in [
    container,
    container.querySelector('.post'),
    container.querySelector('.postMessage'),
  ]) {
    final Match? match = _postId.firstMatch(element?.id ?? '');
    if (match != null) {
      return int.parse(match.group(1)!);
    }
  }
  return null;
}
