import 'dart:convert';

import 'package:flutter_chan/chan/archives.dart';
import 'package:flutter_chan/chan/http_client.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A thread as FoolFuuka's API answers with it, trimmed to what's read.
Map<String, dynamic> _answer() => <String, dynamic>{
  '100': <String, dynamic>{
    'op': <String, dynamic>{
      'num': '100',
      'subnum': '0',
      'thread_num': '100',
      'timestamp': 1795059910,
      'capcode': 'N',
      'name': 'Anonymous',
      'title': 'Why <so> many languages',
      'comment': 'Just one would do',
      'poster_hash': 'abcd1234',
      'poster_country': 'FR',
      'poster_country_name': 'France',
      'sticky': '0',
      'media': <String, dynamic>{
        'spoiler': '0',
        'media_orig': '1795059910453.jpg',
        'media_filename': 'HQyRCikW.jpg',
        'media_w': '1168',
        'media_h': '802',
        'preview_w': '250',
        'preview_h': '171',
        'media_link': 'https://img.example/g/image/1795059910453.jpg',
        'thumb_link': 'https://img.example/g/thumb/1795059910453s.jpg',
      },
    },
    'posts': <String, dynamic>{
      '102': <String, dynamic>{
        'num': '102',
        'subnum': '0',
        'thread_num': '100',
        'timestamp': 1795060300,
        'capcode': 'M',
        'name': 'Anonymous',
        'comment': '>>101\nagreed',
        'media': null,
      },
      '101': <String, dynamic>{
        'num': '101',
        'subnum': '0',
        'thread_num': '100',
        'timestamp': 1795060216,
        'capcode': 'N',
        'name': 'Anonymous',
        'comment': '>>100\n>implying\nuse [spoiler]C[/spoiler]',
        'media': null,
      },
      // Posted on the archive itself, not on 4chan.
      '101_1': <String, dynamic>{
        'num': '101',
        'subnum': '1',
        'thread_num': '100',
        'timestamp': 1795060400,
        'comment': 'ghost',
      },
    },
  },
};

void main() {
  group('archivedComment', () {
    test('turns quotes, greentext and spoilers into 4chan HTML', () {
      expect(
        archivedComment(
          '>>101\n>implying\nuse [spoiler]C[/spoiler] & <b>',
          board: 'g',
          here: {101},
        ),
        <String>[
          '<a href="#p101" class="quotelink">&gt;&gt;101</a>',
          '<span class="quote">&gt;implying</span>',
          'use <s>C</s> &amp; &lt;b&gt;',
        ].join('<br>'),
      );
    });

    test('keeps code as a block, its lines in it', () {
      expect(
        archivedComment('look:\n[code]int a;\nint b;[/code]\nok', board: 'g'),
        'look:<br><pre class="prettyprint">int a;<br>int b;</pre><br>ok',
      );
    });

    test('links other boards, and posts in other threads', () {
      expect(
        archivedComment(
          '>>>/g/123\nsee >>>/v/ and >>456, >>100',
          board: 'sci',
          here: {100},
        ),
        <String>[
          '<a href="/g/thread/123" class="quotelink">&gt;&gt;&gt;/g/123</a>',
          <String>[
            'see <a href="//boards.4chan.org/v/" class="quotelink">',
            '&gt;&gt;&gt;/v/</a> and ',
            '<a href="/sci/thread/456" class="quotelink">&gt;&gt;456</a>, ',
            '<a href="#p100" class="quotelink">&gt;&gt;100</a>',
          ].join(),
        ].join('<br>'),
      );
    });

    test('drops the BBCode 4chan shows no sign of', () {
      expect(
        archivedComment('[b]bold[/b] [banned]x[/banned]', board: 'g'),
        'bold x',
      );
    });
  });

  group('parseArchivedThread', () {
    test('reads the posts oldest first, leaving out ghost posts', () {
      final List<Post> posts = parseArchivedThread(_answer(), 'g', 100)!;
      expect(posts.map((Post post) => post.no), [100, 101, 102]);

      final Post op = posts.first;
      expect(op.resto, 0);
      expect(op.sub, 'Why &lt;so&gt; many languages');
      expect(op.subject, 'Why <so> many languages');
      expect(op.id, 'abcd1234');
      expect(op.countryName, 'France');
      expect(op.closed, 1);
      expect(op.tim, 1795059910453);
      expect(op.ext, '.jpg');
      expect(op.filename, 'HQyRCikW');
      expect(op.w, 1168);
      expect(op.tnW, 250);
      expect(op.fileUrl, 'https://img.example/g/image/1795059910453.jpg');
      expect(op.thumbnailUrl, 'https://img.example/g/thumb/1795059910453s.jpg');

      expect(posts[1].resto, 100);
      expect(posts[1].hasFile, isFalse);
      expect(posts[1].com, contains('class="quotelink">&gt;&gt;100</a>'));
      expect(posts[2].capcode, 'mod');
    });

    test("is null when the archive hasn't got it", () {
      expect(
        parseArchivedThread(
          <String, dynamic>{'error': 'Thread not found.'},
          'g',
          100,
        ),
        isNull,
      );
    });

    test('a copy of the posts keeps where their files are', () {
      final Post op = parseArchivedThread(_answer(), 'g', 100)!.first;
      final Post copy = Post.fromJson(
        jsonDecode(jsonEncode(op.toJson())) as Map<String, dynamic>,
        'g',
      );
      expect(copy.fileUrl, op.fileUrl);
      expect(copy.thumbnailUrl, op.thumbnailUrl);
    });
  });

  test('posts merge with the copy on show, the archive winning', () {
    final List<Post> merged = mergeArchivedPosts(
      <Post>[
        Post(board: 'g', no: 1, com: 'copy'),
        Post(board: 'g', no: 3, com: 'only in the copy'),
      ],
      <Post>[
        Post(board: 'g', no: 1, com: 'archive'),
        Post(board: 'g', no: 2, com: 'only in the archive'),
      ],
    );
    expect(merged.map((Post post) => post.com), [
      'archive',
      'only in the archive',
      'only in the copy',
    ]);
  });

  test("a thread from an archive remembers the archive's thumbnail", () {
    final Post op = parseArchivedThread(_answer(), 'g', 100)!.first;
    final Post remembered = Post.remembered(
      board: 'g',
      no: 100,
      thumbnailName: op.thumbnailName,
    );
    expect(remembered.thumbnailUrl, op.thumbnailUrl);
    // One from 4chan, as before.
    expect(
      Post.remembered(board: 'g', no: 1, thumbnailName: '5s.jpg').thumbnailUrl,
      'https://i.4cdn.org/g/5s.jpg',
    );
  });

  test(
    'the boards an archive lists take the place of those built in',
    () async {
      SharedPreferences.setMockInitialValues({});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      addTearDown(forgetArchiveBoards);
      // Not asked unless they're looked in.
      await rememberArchiveBoards(
        prefs,
        client: MockClient((_) async => fail('asked without looking')),
      );
      await rememberArchiveBoards(
        prefs,
        ask: true,
        off: {'thebarchive.com'},
        client: MockClient((http.Request request) async {
          expect(request.url.host, isNot('thebarchive.com'));
          return request.url.host == 'desuarchive.org'
              ? http.Response(
                  jsonEncode({
                    'archives': {
                      '1': {'shortname': 'sci'},
                      '2': {'shortname': 'g'},
                    },
                  }),
                  200,
                )
              : http.Response('down', 503);
        }),
      );
      expect(archivesFor('sci').first.name, 'Desuarchive');
      expect(archivesFor('a').map((ThreadArchive a) => a.name), [
        'archived.moe',
      ]);
      // Remembered for next time, without asking again so soon.
      forgetArchiveBoards();
      await rememberArchiveBoards(
        prefs,
        ask: true,
        client: MockClient((_) async => fail('asked again')),
      );
      expect(archivesFor('sci').first.name, 'Desuarchive');
    },
  );

  test('warosu lists its boards on its front page', () {
    expect(boardsOnWarosu('<a href="/jp/">jp</a> / <a href="/3/">3</a>'), [
      '3',
      'jp',
    ]);
  });

  test('a post from 4chan still has its files there', () {
    final Post post = Post(board: 'g', no: 1, tim: 5, ext: '.png');
    expect(post.fileUrl, 'https://i.4cdn.org/g/5.png');
    expect(post.thumbnailUrl, 'https://i.4cdn.org/g/5s.jpg');
  });

  test(
    'archivesFor lists the archives keeping the board, archived.moe last',
    () {
      expect(archivesFor('g').map((ThreadArchive a) => a.name), [
        'Desuarchive',
        'b4k',
        'archived.moe',
      ]);
      expect(archivesFor('pol').map((ThreadArchive a) => a.name), [
        '4plebs',
        'archived.moe',
      ]);
      expect(archivesFor('nope').map((ThreadArchive a) => a.name), [
        'archived.moe',
      ]);
    },
  );

  group('jsonInPage', () {
    test('reads the JSON a web view shows', () {
      expect(
        jsonInPage(
          '<html><head></head><body><pre>{"a":"&lt;b&gt;"}</pre></body></html>',
        ),
        '{"a":"<b>"}',
      );
    });

    test("is null for Cloudflare's check", () {
      expect(
        jsonInPage(
          '<html><head><title>Just a moment...</title></head> '
          '<body>Checking your browser</body></html>',
        ),
        isNull,
      );
    });
  });

  group('fetchArchivedThread', () {
    test('asks one archive after another until one has it', () async {
      final List<String> asked = <String>[];
      final client = MockClient((http.Request request) async {
        asked.add(request.url.host);
        expect(request.url.queryParameters, {'board': 'g', 'num': '100'});
        return request.url.host == 'desuarchive.org'
            ? http.Response('{"error":"Thread not found."}', 200)
            : http.Response(jsonEncode(_answer()), 200);
      });

      final found = await fetchArchivedThread('g', 100, client: client);
      expect(asked, ['desuarchive.org', 'arch.b4k.dev']);
      expect(found!.archive.name, 'b4k');
      expect(found.posts, hasLength(3));
    });

    test('reads the archive behind a check with browse, last', () async {
      final List<String> asked = <String>[];
      final client = MockClient((http.Request request) async {
        asked.add(request.url.host);
        return http.Response('{"error":"Thread not found."}', 200);
      });
      final found = await fetchArchivedThread(
        'g',
        100,
        client: client,
        browse: (Uri api) async {
          asked.add(api.host);
          expect(api.queryParameters, {'board': 'g', 'num': '100'});
          return jsonEncode(_answer());
        },
      );
      expect(asked, ['desuarchive.org', 'arch.b4k.dev', 'archived.moe']);
      expect(found!.archive.name, 'archived.moe');
      expect(found.posts, hasLength(3));
    });

    test('a check that never passes counts as no answer', () async {
      final client = MockClient((_) async => http.Response('down', 503));
      await expectLater(
        fetchArchivedThread(
          'g',
          100,
          client: client,
          browse: (_) async => null,
        ),
        throwsA(isA<ArchivesUnreachable>()),
      );
    });

    test('is null when every archive answers it has not got it', () async {
      final client = MockClient(
        (_) async => http.Response('{"error":"Thread not found."}', 200),
      );
      expect(await fetchArchivedThread('g', 100, client: client), isNull);
    });

    test('says so when no archive answers', () async {
      final client = MockClient((_) async => http.Response('down', 503));
      await expectLater(
        fetchArchivedThread('g', 100, client: client),
        throwsA(isA<ArchivesUnreachable>()),
      );
    });
  });

  test('archives are told who is asking; 4chan is not', () async {
    final Map<String, String?> agents = <String, String?>{};
    final client = ArchiveAgentClient(
      MockClient((http.Request request) async {
        agents[request.url.host] = request.headers['User-Agent'];
        return http.Response('', 200);
      }),
    );
    await client.get(Uri.https('desuarchive.org', '/'));
    await client.get(Uri.https('a.4cdn.org', '/g/catalog.json'));
    expect(agents, {'desuarchive.org': 'NekoSurf', 'a.4cdn.org': null});
  });
}
