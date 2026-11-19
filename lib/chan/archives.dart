import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_chan/chan/archive_links.dart';
import 'package:flutter_chan/chan/http_client.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/chan/warosu.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A site, run by others, that keeps 4chan's threads after 4chan deletes them;
/// each keeps only some boards. Most run FoolFuuka and answer alike; warosu
/// runs Fuuka, which has no API, so its thread pages are read instead.
class ThreadArchive {
  const ThreadArchive(
    this.name,
    this.host,
    this._boards, {
    this.behindCheck = false,
    this.pagesOnly = false,
  });

  final String name;
  final String host;

  /// The boards it keeps, separated by spaces; `*` for every board. What
  /// it lists itself now takes its place ([rememberArchiveBoards]).
  final String _boards;

  List<String> get _boardList => _listedBoards[host] ?? _boards.split(' ');

  /// Whether it puts a Cloudflare check in front of its API, so it can only
  /// be read in a web view.
  final bool behindCheck;

  /// Whether it has no API, so its thread pages are read (warosu's).
  final bool pagesOnly;

  /// The boards it keeps, for people: "/g/, /a/, /co/ and 19 more".
  String get boardsDescription {
    if (_boards == '*') {
      return 'Every board';
    }
    final List<String> boards = _boardList;
    final String shown = boards.take(3).map((String b) => '/$b/').join(', ');
    return boards.length <= 3 ? shown : '$shown and ${boards.length - 3} more';
  }

  /// Whether it keeps [board]'s threads.
  bool keeps(String board) => _boards == '*' || _boardList.contains(board);

  /// Where it lists the boards it keeps: FoolFuuka's API, warosu's front
  /// page; null for one that keeps every board.
  Uri? get boardList => _boards == '*'
      ? null
      : pagesOnly
      ? Uri.https(host, '/')
      : Uri.https(host, '/_/api/chan/archives/');

  /// [board]'s [thread], as FoolFuuka's API gives it, or as its page.
  Uri thread(String board, int thread) => pagesOnly
      ? Uri.https(host, '/$board/thread/$thread')
      : Uri.https(host, '/_/api/chan/thread/', <String, String>{
          'board': board,
          'num': '$thread',
        });
}

/// The archives, and the boards each keeps, as their `/_/api/chan/archives/`
/// listed them in November 2026 (warosu: its front page), in the order
/// they're asked. archived.moe
/// keeps every board, many without images, and asks for a browser check
/// first, so it's asked last.
const List<ThreadArchive> threadArchives = <ThreadArchive>[
  ThreadArchive(
    'Desuarchive',
    'desuarchive.org',
    'a aco an c cgl co d fit g his int k m mlp mu q qa r9k tg trash vr wsg',
  ),
  ThreadArchive('b4k', 'arch.b4k.dev', 'g mlp qb v vg vm vmg vp vrpg vst'),
  ThreadArchive(
    'Palanq',
    'archive.palanq.win',
    'bant c con e i n news out p pw qst toy vip vp vt w wg wsr',
  ),
  ThreadArchive(
    'Archive of Sins',
    'archiveofsins.com',
    'h hc hm i lgbt r s soc t u',
  ),
  ThreadArchive('TheBArchive', 'thebarchive.com', 'b bant'),
  ThreadArchive(
    '4plebs',
    'archive.4plebs.org',
    'adv f hr mlpol mo o pol s4s sp tg trv tv x',
  ),
  ThreadArchive(
    'warosu',
    'warosu.org',
    '3 biz cgl ck diy fa ic jp lit sci vr vt',
    pagesOnly: true,
  ),
  ThreadArchive('archived.moe', 'archived.moe', '*', behindCheck: true),
];

/// The boards each archive listed itself, by host, as last asked.
final Map<String, List<String>> _listedBoards = <String, List<String>>{};

const String _boardsKey = 'archiveBoards';

/// How often the archives are asked which boards they keep.
const Duration _boardsCheck = Duration(days: 7);

/// Uses the boards the archives listed last time, kept in [prefs]. With
/// [ask], as when looking in them, asks those not [off] (hosts) again if
/// that was a while ago, so a board an archive starts or stops keeping is
/// known; the archives are only asked when they're looked in.
Future<void> rememberArchiveBoards(
  SharedPreferences prefs, {
  bool ask = false,
  Set<String> off = const <String>{},
  @visibleForTesting Client? client,
}) async {
  int checkedAt = 0;
  try {
    final Object? kept = jsonDecode(prefs.getString(_boardsKey) ?? '{}');
    if (kept is Map) {
      checkedAt = kept['at'] as int? ?? 0;
      final Object? boards = kept['boards'];
      if (boards is Map) {
        for (final MapEntry<Object?, Object?> entry in boards.entries) {
          if (entry.key case final String host) {
            if (entry.value case final List<Object?> list) {
              _listedBoards[host] = list.whereType<String>().toList();
            }
          }
        }
      }
    }
  } catch (_) {}
  final DateTime last = DateTime.fromMillisecondsSinceEpoch(checkedAt);
  if (!ask || DateTime.now().difference(last) < _boardsCheck) {
    return;
  }
  for (final ThreadArchive archive in threadArchives) {
    final Uri? url = archive.boardList;
    if (url == null || archive.behindCheck || off.contains(archive.host)) {
      continue;
    }
    try {
      final Response response = await (client ?? httpClient).get(url);
      if (response.statusCode != 200) {
        continue;
      }
      final List<String> boards = archive.pagesOnly
          ? boardsOnWarosu(response.body)
          : boardsInArchiveList(response.body);
      if (boards.isNotEmpty) {
        _listedBoards[archive.host] = boards;
      }
    } catch (e) {
      debugPrint('Could not ask ${archive.name} for its boards: $e');
    }
  }
  await prefs.setString(
    _boardsKey,
    jsonEncode(<String, Object>{
      'at': DateTime.now().millisecondsSinceEpoch,
      'boards': _listedBoards,
    }),
  );
}

/// Forgets the boards the archives listed, for tests.
@visibleForTesting
void forgetArchiveBoards() => _listedBoards.clear();

/// The boards in FoolFuuka's `/_/api/chan/archives/` answer.
@visibleForTesting
List<String> boardsInArchiveList(String body) {
  final Object? json = jsonDecode(body);
  final Object? archives = json is Map ? json['archives'] ?? json : json;
  final Iterable<Object?> each = archives is Map
      ? archives.values
      : archives is List
      ? archives
      : const <Object?>[];
  return <String>[
    for (final Object? archive in each)
      if (archive is Map && archive['shortname'] is String)
        archive['shortname'] as String,
  ]..sort();
}

final RegExp _warosuBoard = RegExp(r'href="/(\w+)/"');

/// The boards linked from warosu's front page.
@visibleForTesting
List<String> boardsOnWarosu(String html) => <String>{
  for (final Match match in _warosuBoard.allMatches(html)) match[1]!,
}.toList()..sort();

/// The archives that keep [board], to look in one after another.
List<ThreadArchive> archivesFor(String board) => <ThreadArchive>[
  for (final ThreadArchive archive in threadArchives)
    if (archive.keeps(board)) archive,
];

/// None of the archives could be asked: no connection, most likely.
class ArchivesUnreachable implements Exception {
  const ArchivesUnreachable();

  @override
  String toString() => "Couldn't reach the archives.";
}

/// What asking one archive came to: whether it answered, and the posts if
/// it has the thread.
typedef _Answer = ({bool answered, List<Post>? posts});

/// [board]'s [thread] from the first of [archives] (by default, all that
/// keep the board) that has it, oldest post first; null if every one
/// answered that it hasn't. Throws [ArchivesUnreachable] if none answered.
///
/// The archives that answer an app are all asked at once, so one that's
/// slow to answer doesn't hold up the rest; the first in order that has it
/// wins. Archives [ThreadArchive.behindCheck] are asked after them, with
/// [browse], which gives the API's answer as read in a web view, or null
/// if it couldn't; without [browse] they're left out.
Future<({List<Post> posts, ThreadArchive archive})?> fetchArchivedThread(
  String board,
  int thread, {
  List<ThreadArchive>? archives,
  Future<String?> Function(Uri api)? browse,
  @visibleForTesting Client? client,
}) async {
  final List<ThreadArchive> asked = archives ?? archivesFor(board);
  final Map<ThreadArchive, Future<_Answer>> direct = {
    for (final ThreadArchive archive in asked)
      if (!archive.behindCheck)
        archive: _ask(archive, board, thread, client ?? httpClient),
  };
  bool anyAnswered = false;
  for (final ThreadArchive archive in <ThreadArchive>[
    ...asked.where((ThreadArchive a) => !a.behindCheck),
    ...asked.where((ThreadArchive a) => a.behindCheck),
  ]) {
    final _Answer answer =
        await direct[archive] ?? await _browse(archive, board, thread, browse);
    anyAnswered |= answer.answered;
    final List<Post>? posts = answer.posts;
    if (posts != null && posts.isNotEmpty) {
      return (posts: posts, archive: archive);
    }
  }
  if (!anyAnswered) {
    throw const ArchivesUnreachable();
  }
  return null;
}

Future<_Answer> _ask(
  ThreadArchive archive,
  String board,
  int thread,
  Client client,
) async {
  try {
    final Response response = await client.get(archive.thread(board, thread));
    if (response.statusCode == 404) {
      return (answered: true, posts: null);
    }
    if (response.statusCode != 200) {
      return (answered: false, posts: null);
    }
    return (
      answered: true,
      posts: await _read(archive, response.body, board, thread),
    );
  } catch (e) {
    debugPrint('Could not ask ${archive.name}: $e');
    return (answered: false, posts: null);
  }
}

Future<_Answer> _browse(
  ThreadArchive archive,
  String board,
  int thread,
  Future<String?> Function(Uri api)? browse,
) async {
  try {
    final String? body = browse == null
        ? null
        : await browse(archive.thread(board, thread));
    if (body == null) {
      return (answered: false, posts: null);
    }
    return (answered: true, posts: await _read(archive, body, board, thread));
  } catch (e) {
    debugPrint('Could not ask ${archive.name}: $e');
    return (answered: false, posts: null);
  }
}

Future<List<Post>?> _read(
  ThreadArchive archive,
  String body,
  String board,
  int thread,
) async {
  try {
    return await compute(archive.pagesOnly ? _parsePage : _parse, (
      body: body,
      board: board,
      thread: thread,
    ));
  } catch (e) {
    debugPrint('Could not read what ${archive.name} answered: $e');
    return null;
  }
}

/// The posts on show ([shown], maybe a copy from 4chan) with those an
/// archive has of the thread ([archived]): the archive's version of each,
/// as 4chan's files are gone, and every post only one of them has, oldest
/// first.
List<Post> mergeArchivedPosts(List<Post> shown, List<Post> archived) {
  final Map<int, Post> byNumber = <int, Post>{
    for (final Post post in shown) post.no: post,
    for (final Post post in archived) post.no: post,
  };
  return byNumber.values.toList()
    ..sort((Post a, Post b) => a.no.compareTo(b.no));
}

/// The JSON an API page shows in a web view, out of the page's [html]; null
/// if the page isn't JSON, such as Cloudflare's check.
String? jsonInPage(String html) {
  final String? text = html_parser.parse(html).body?.text.trim();
  if (text == null || !text.startsWith('{')) {
    return null;
  }
  try {
    return jsonDecode(text) is Map ? text : null;
  } on FormatException {
    return null;
  }
}

List<Post>? _parsePage(({String body, String board, int thread}) fetched) =>
    parseWarosuThread(fetched.body, fetched.board, fetched.thread);

List<Post>? _parse(({String body, String board, int thread}) fetched) {
  final Object? json = jsonDecode(fetched.body);
  return json is Map<String, dynamic>
      ? parseArchivedThread(json, fetched.board, fetched.thread)
      : null;
}

/// The posts of [thread] in a FoolFuuka answer, as 4chan's API would give
/// them; null if the answer is that the archive hasn't got it.
@visibleForTesting
List<Post>? parseArchivedThread(
  Map<String, dynamic> json,
  String board,
  int thread,
) {
  final Object? found = json['$thread'];
  if (found is! Map<String, dynamic> || found['op'] is! Map) {
    return null;
  }
  final Object? replies = found['posts'];
  final List<Object?> all = <Object?>[
    found['op'],
    if (replies is Map) ...replies.values,
    if (replies is List) ...replies,
  ];
  // Posts made on the archive itself (subnum) aren't 4chan's.
  final Set<int> here = <int>{
    for (final Object? each in all)
      if (each is Map<String, dynamic> && (_int(each['subnum']) ?? 0) == 0)
        ?_int(each['num']),
  };
  final List<Post> posts = <Post>[
    for (final Object? each in all)
      if (each is Map<String, dynamic>) ?_post(each, board, thread, here),
  ]..sort((Post a, Post b) => a.no.compareTo(b.no));
  return posts;
}

int? _int(Object? value) => switch (value) {
  final int number => number,
  final String text => int.tryParse(text),
  _ => null,
};

String? _text(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

const Map<String, String> _capcodes = <String, String>{
  'M': 'mod',
  'A': 'admin',
  'D': 'developer',
  'F': 'founder',
  'V': 'verified',
  'G': 'manager',
};

/// What an archive says of a post's file.
typedef _ArchivedFile = ({
  int? tim,
  String? ext,
  String? filename,
  String? url,
  String? thumbnail,
  int? w,
  int? h,
  int? tnW,
  int? tnH,
  bool spoiler,
});

Post? _post(
  Map<String, dynamic> data,
  String board,
  int thread,
  Set<int> here,
) {
  final int? no = _int(data['num']);
  // A post made on the archive itself, not on 4chan.
  if (no == null || (_int(data['subnum']) ?? 0) != 0) {
    return null;
  }
  final Object? media = data['media'];
  final ({
    int? tim,
    String? ext,
    String? filename,
    String? url,
    String? thumbnail,
    int? w,
    int? h,
    int? tnW,
    int? tnH,
    bool spoiler,
  })?
  file = media is Map ? _file(media) : null;
  final bool isOp = no == thread;
  final String? country = _text(data['poster_country']);
  return Post(
    board: board,
    no: no,
    resto: isOp ? 0 : thread,
    time: _int(data['timestamp']),
    name: _escape(_text(data['name'])),
    trip: _escape(_text(data['trip'])),
    sub: _escape(_text(data['title'])),
    com: archivedComment(
      _text(data['comment']) ?? '',
      board: board,
      here: here,
    ),
    id: _text(data['poster_hash']),
    country: country,
    countryName: country == null ? null : _text(data['poster_country_name']),
    capcode: _capcodes[data['capcode']],
    sticky: isOp && _int(data['sticky']) == 1 ? 1 : null,
    closed: isOp ? 1 : null,
    tim: file?.tim,
    ext: file?.ext,
    filename: file?.filename,
    w: file?.w,
    h: file?.h,
    tnW: file?.tnW,
    tnH: file?.tnH,
    spoiler: (file?.spoiler ?? false) ? 1 : null,
    archivedFileUrl: file?.url,
    archivedThumbnailUrl: file?.thumbnail,
  );
}

_ArchivedFile? _file(Map<dynamic, dynamic> media) {
  // "1700000000000.webm": 4chan's own name for it.
  final String? stored = _text(media['media_orig']) ?? _text(media['media']);
  final String? url =
      _text(media['media_link']) ?? _text(media['remote_media_link']);
  final int dot = stored?.lastIndexOf('.') ?? -1;
  if (stored == null || url == null || dot <= 0) {
    return null;
  }
  final String? filename = _text(media['media_filename']);
  final int nameDot = filename?.lastIndexOf('.') ?? -1;
  return (
    tim: int.tryParse(stored.substring(0, dot)),
    ext: stored.substring(dot),
    filename: filename == null || nameDot <= 0
        ? filename
        : filename.substring(0, nameDot),
    url: url,
    thumbnail: _text(media['thumb_link']),
    w: _int(media['media_w']),
    h: _int(media['media_h']),
    tnW: _int(media['preview_w']),
    tnH: _int(media['preview_h']),
    spoiler: _int(media['spoiler']) == 1,
  );
}

String? _escape(String? text) => text == null ? null : _html(text);

String _html(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

// `>>>/g/123`, `>>>/g/`, or `>>123`.
final RegExp _quote = RegExp(r'&gt;&gt;&gt;/(\w+)/(\d*)|&gt;&gt;(\d+)');
final RegExp _otherTags = RegExp(
  r'\[/?(?:b|i|u|o|s|banned|moot|sjis|shiftjis|eqn|math|fortune[^\]]*)\]',
);

/// A post's text as FoolFuuka keeps it (plain, with BBCode) as 4chan writes
/// it: HTML with quote links, greentext, spoilers and code blocks. Quotes of
/// posts that aren't [here], in the thread, go to other threads on [board].
@visibleForTesting
String archivedComment(
  String raw, {
  required String board,
  Set<int> here = const <int>{},
}) {
  final List<String> lines = <String>[];
  bool inCode = false;
  for (final String line in raw.replaceAll('\r', '').split('\n')) {
    String html = _html(line);
    if (inCode) {
      if (html.contains('[/code]')) {
        inCode = false;
        html = html.replaceFirst('[/code]', '</pre>');
      }
      lines.add(html);
      continue;
    }
    if (html.contains('[code]')) {
      inCode = !html.contains('[/code]');
      lines.add(
        html
            .replaceFirst('[code]', '<pre class="prettyprint">')
            .replaceFirst('[/code]', '</pre>'),
      );
      continue;
    }
    html = html
        .replaceAll(_otherTags, '')
        .replaceAll('[spoiler]', '<s>')
        .replaceAll('[/spoiler]', '</s>');
    final bool green = html.startsWith('&gt;') && !html.startsWith(_quote);
    html = html.replaceAllMapped(
      _quote,
      (Match match) => match[3] != null
          ? quoteLink(int.parse(match[3]!), board: board, here: here)
          : boardLink(match[1]!, int.tryParse(match[2]!)),
    );
    lines.add(green ? '<span class="quote">$html</span>' : html);
  }
  if (inCode) {
    lines.add('</pre>');
  }
  return lines.join('<br>');
}
