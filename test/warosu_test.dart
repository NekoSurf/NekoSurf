import 'package:flutter_chan/chan/archives.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/chan/warosu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A warosu thread page, trimmed to what's read, its markup as warosu's.
const String _page = '''
<html><body>
<form id="postform" action="/sci/" method="post">
<div class="content">
  <div class="comment" id="p100">
    <span class="fileinfo break-all">File: 661 KB, 1500x1050, my plot.png</span>
    <a href="https://i.warosu.org/data/sci/img/0000/01/1780107493775147.png">
      <img class="thumb" src="https://i.warosu.org/data/sci/thumb/0000/01/1780107493775147s.jpg" width="250" height="175">
    </a>
    <label>
      <span class="filetitle">Why <b>math</b></span>&nbsp;
      <span class="postername ">Anonymous</span>
      <span class="postertrip">!Tr1p</span>
      <span class="posttime" title="1780107493000">Sun, May 30, 2026</span>
    </label>
    <a class="js" href="/sci/thread/100">No.</a><a class="js" href="javascript:insert('&gt;&gt;100')">100</a>
    <blockquote><p>
      First &amp; foremost<br>see <a href="https://example.com/a" rel="ugc nofollow" class="break-all">https://example.com/a</a>
    </p></blockquote>
  </div>
  <table><tr><td class="doubledash">&gt;&gt;</td>
    <td class=" comment reply" id="p102">
      <label><span class="postername ">Anonymous</span>
      <span class="posttime" title="1780108813000">x</span></label>
      <a class="js" href="/sci/thread/100#p102">No.</a>
      <blockquote><p>
        <a href="/sci/post/99">&gt;&gt;99</a><br><span class="spoiler">hidden</span>
      </p></blockquote>
    </td>
  </tr></table>
  <table><tr><td class="doubledash">&gt;&gt;</td>
    <td class=" comment reply" id="p101">
      <label><span class="postername ">Anonymous</span>
      <span class="posttime" title="1780108000000">x</span></label>
      <a class="js" href="/sci/thread/100#p101">No.</a>
      <blockquote><p>
        <a href="#p100" class="backlink">&gt;&gt;100</a><br><span class="unkfunc">&gt;implying</span><br>ok
      </p></blockquote>
    </td>
  </tr></table>
  <table><tbody><tr><td class="doubledash">&gt;&gt;</td>
    <td class="subreply"><div class="theader">Reply to thread</div></td>
  </tr></tbody></table>
</div>
</form>
</body></html>
''';

void main() {
  test('reads a thread page oldest first, as 4chan would give it', () {
    final List<Post> posts = parseWarosuThread(_page, 'sci', 100)!;
    expect(posts.map((Post post) => post.no), [100, 101, 102]);

    final Post op = posts.first;
    expect(op.resto, 0);
    expect(op.closed, 1);
    expect(op.time, 1780107493);
    expect(op.sub, 'Why math');
    expect(op.trip, '!Tr1p');
    expect(op.tim, 1780107493775147);
    expect(op.ext, '.png');
    expect(op.filename, 'my plot');
    expect((op.w, op.h, op.tnW, op.tnH), (1500, 1050, 250, 175));
    expect(
      op.fileUrl,
      'https://i.warosu.org/data/sci/img/0000/01/1780107493775147.png',
    );
    expect(
      op.thumbnailUrl,
      'https://i.warosu.org/data/sci/thumb/0000/01/1780107493775147s.jpg',
    );
    expect(op.com, 'First &amp; foremost<br>see https://example.com/a');

    expect(posts[1].resto, 100);
    expect(posts[1].hasFile, isFalse);
    expect(
      posts[1].com,
      <String>[
        '<a href="#p100" class="quotelink">&gt;&gt;100</a>',
        '<span class="quote">&gt;implying</span>',
        'ok',
      ].join('<br>'),
    );
    expect(
      posts[2].com,
      // Not in the thread: in another one.
      <String>[
        '<a href="/sci/thread/99" class="quotelink">&gt;&gt;99</a>',
        '<s>hidden</s>',
      ].join('<br>'),
    );
  });

  test("a reply's page isn't taken for a thread", () {
    // Warosu answers a reply's number with that one post.
    expect(parseWarosuThread(_page, 'sci', 101), isNull);
    expect(
      parseWarosuThread(_page.replaceAll('id="p100"', 'id="p7"'), 'sci', 7),
      isNull,
    );
  });

  test('is null for a page without posts', () {
    expect(parseWarosuThread('<html><body></body></html>', 'sci', 1), isNull);
  });

  test('warosu is asked for its page, before archived.moe', () async {
    expect(archivesFor('sci').map((ThreadArchive a) => a.name), [
      'warosu',
      'archived.moe',
    ]);
    final List<Uri> asked = <Uri>[];
    final found = await fetchArchivedThread(
      'sci',
      100,
      client: MockClient((http.Request request) async {
        asked.add(request.url);
        return http.Response(_page, 200);
      }),
    );
    expect(asked, [Uri.https('warosu.org', '/sci/thread/100')]);
    expect(found!.archive.name, 'warosu');
    expect(found.posts, hasLength(3));
  });

  test("warosu's 404 is an answer that it hasn't got it", () async {
    final found = await fetchArchivedThread(
      'sci',
      100,
      client: MockClient((_) async => http.Response('Not found', 404)),
    );
    expect(found, isNull);
  });
}
