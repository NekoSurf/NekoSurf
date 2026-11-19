import 'package:flutter/foundation.dart';
import 'package:flutter_chan/chan/archive_links.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

// Warosu runs Fuuka, which has no API: its thread pages are read instead.
// If it changes their markup, reading fails and the thread isn't found.

/// The posts of [thread] on a warosu thread page, as 4chan's API would give
/// them; null if the page isn't that thread (warosu shows a reply's number
/// as a page of that one post).
List<Post>? parseWarosuThread(String html, String board, int thread) {
  final Document page = html_parser.parse(html);
  final List<Element> found = page.querySelectorAll('.comment[id^="p"]');
  // An opening post links to its thread; a reply to its place in one.
  if (found.isEmpty ||
      found.first.id != 'p$thread' ||
      found.first.querySelector('a.js')?.attributes['href'] !=
          '/$board/thread/$thread') {
    return null;
  }
  final Set<int> here = <int>{
    for (final Element each in found) ?int.tryParse(each.id.substring(1)),
  };
  final List<Post> posts = <Post>[
    for (final Element each in found) ?_post(each, board, thread, here),
  ]..sort((Post a, Post b) => a.no.compareTo(b.no));
  return posts.isEmpty || posts.first.no != thread ? null : posts;
}

String? _text(Element? element) {
  final String? text = element?.text.trim();
  return text == null || text.isEmpty ? null : text;
}

Post? _post(Element element, String board, int thread, Set<int> here) {
  final int? no = int.tryParse(element.id.substring(1));
  if (no == null) {
    return null;
  }
  final bool isOp = no == thread;
  final int? millis = int.tryParse(
    element.querySelector('.posttime')?.attributes['title'] ?? '',
  );
  final ({
    int? tim,
    String? ext,
    String? filename,
    String url,
    String? thumbnail,
    int? w,
    int? h,
    int? tnW,
    int? tnH,
  })?
  file = _file(element);
  final Element? comment = element.querySelector('blockquote');
  return Post(
    board: board,
    no: no,
    resto: isOp ? 0 : thread,
    time: millis == null ? null : millis ~/ 1000,
    name: _escape(_text(element.querySelector('.postername'))),
    trip: _escape(_text(element.querySelector('.postertrip'))),
    sub: _escape(_text(element.querySelector('.filetitle'))),
    com: comment == null
        ? ''
        : warosuComment(comment, board: board, here: here),
    closed: isOp ? 1 : null,
    tim: file?.tim,
    ext: file?.ext,
    filename: file?.filename,
    w: file?.w,
    h: file?.h,
    tnW: file?.tnW,
    tnH: file?.tnH,
    archivedFileUrl: file?.url,
    archivedThumbnailUrl: file?.thumbnail,
  );
}

// "File: 661 KB, 1500x1050, I.png"
final RegExp _fileInfo = RegExp(r'(\d+)x(\d+), (.+)$');

({
  int? tim,
  String? ext,
  String? filename,
  String url,
  String? thumbnail,
  int? w,
  int? h,
  int? tnW,
  int? tnH,
})?
_file(Element post) {
  final Element? thumb = post.querySelector('img.thumb');
  final String? url = thumb?.parent?.attributes['href'];
  if (thumb == null || url == null) {
    return null;
  }
  // ".../img/0169/90/1780107493775147.png": 4chan's own name for it.
  final String stored = Uri.tryParse(url)?.pathSegments.lastOrNull ?? '';
  final int dot = stored.lastIndexOf('.');
  if (dot <= 0) {
    return null;
  }
  final RegExpMatch? info = _fileInfo.firstMatch(
    _text(post.querySelector('.fileinfo')) ?? '',
  );
  final String? name = info?[3];
  final int nameDot = name?.lastIndexOf('.') ?? -1;
  return (
    tim: int.tryParse(stored.substring(0, dot)),
    ext: stored.substring(dot),
    filename: name == null || nameDot <= 0 ? name : name.substring(0, nameDot),
    url: url,
    thumbnail: thumb.attributes['src'],
    w: int.tryParse(info?[1] ?? ''),
    h: int.tryParse(info?[2] ?? ''),
    tnW: int.tryParse(thumb.attributes['width'] ?? ''),
    tnH: int.tryParse(thumb.attributes['height'] ?? ''),
  );
}

String? _escape(String? text) => text == null ? null : _html(text);

String _html(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

final RegExp _quote = RegExp(r'^>>(\d+)$');
final RegExp _boardQuote = RegExp(r'^>>>/(\w+)/(\d*)$');

/// A post's text as warosu shows it as 4chan writes it: quote links,
/// greentext, spoilers and code, with links to other sites as plain text,
/// which the app turns into links itself. Quotes of posts that aren't
/// [here], in the thread, go to other threads on [board].
@visibleForTesting
String warosuComment(
  Element blockquote, {
  required String board,
  Set<int> here = const <int>{},
}) {
  final StringBuffer out = StringBuffer();
  void write(Node node) {
    if (node is Text) {
      out.write(_html(node.text));
      return;
    }
    if (node is! Element) {
      return;
    }
    final Iterable<String> classes = node.classes;
    switch (node.localName) {
      case 'br':
        out.write('<br>');
      case 'a':
        final String text = node.text.trim();
        final RegExpMatch? quote = _quote.firstMatch(text);
        final RegExpMatch? other = _boardQuote.firstMatch(text);
        out.write(
          quote != null
              ? quoteLink(int.parse(quote[1]!), board: board, here: here)
              : other != null
              ? boardLink(other[1]!, int.tryParse(other[2]!))
              : _html(node.text),
        );
      case 'span' when classes.contains('unkfunc'):
        out.write('<span class="quote">');
        node.nodes.forEach(write);
        out.write('</span>');
      case 's':
      case 'span' when classes.contains('spoiler'):
        out.write('<s>');
        node.nodes.forEach(write);
        out.write('</s>');
      case 'pre':
        out.write('<pre class="prettyprint">');
        node.nodes.forEach(write);
        out.write('</pre>');
      default:
        node.nodes.forEach(write);
    }
  }

  final Element? paragraph = blockquote.querySelector('p');
  (paragraph ?? blockquote).nodes.forEach(write);
  return out.toString().trim();
}
