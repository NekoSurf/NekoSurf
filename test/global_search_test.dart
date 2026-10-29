import 'package:flutter_chan/API/global_search.dart';
import 'package:flutter_test/flutter_test.dart';

// Shaped like 4chan's board markup, which find.4chan.org reuses.
const String _results = '''
<html><body>
<form action="//find.4chan.org/" method="get"><input type="text" name="q" value="linux"></form>
<div class="boardBanner"><div class="boardTitle">4chan Search `linux` 1,234 comments</div></div>
<div class="board">
  <div class="thread" id="t100">
    <div class="postContainer opContainer" id="pc100">
      <div class="post op" id="p100">
        <div class="postInfoM mobile" id="pim100">
          <span class="nameBlock"><span class="name">Anonymous</span><br><span class="subject">Linux general</span></span>
          <span class="dateTime postNum" data-utc="1700000000">11/14/23(Tue)22:13:20 <a href="//boards.4chan.org/g/thread/100#p100" title="Link to this post">No.</a><a href="//boards.4chan.org/g/thread/100#q100">100</a></span>
        </div>
        <div class="file" id="f100">
          <a class="fileThumb" href="//i.4cdn.org/g/1700000000123.png" target="_blank"><img src="//i.4cdn.org/g/1700000000123s.jpg" alt="1 KB"></a>
        </div>
        <div class="postInfo desktop" id="pi100">
          <span class="subject">Linux general</span>
          <span class="nameBlock"><span class="name">Anonymous</span></span>
          <span class="dateTime" data-utc="1700000000">11/14/23(Tue)22:13:20</span>
        </div>
        <blockquote class="postMessage" id="m100">Which distro?<br>&gt;inb4 arch</blockquote>
      </div>
    </div>
  </div>
  <div class="thread" id="t200">
    <div class="postContainer replyContainer" id="pc205">
      <div class="post reply" id="p205">
        <div class="postInfo desktop" id="pi205">
          <span class="nameBlock"><span class="name">Anonymous</span></span>
          <span class="dateTime" data-utc="1700000500">11/14/23(Tue)22:21:40</span>
          <span class="postNum desktop"><a href="//boards.4chan.org/tech/thread/200/some-slug#p205">No.</a><a href="//boards.4chan.org/tech/thread/200#q205">205</a></span>
        </div>
        <blockquote class="postMessage" id="m205"><a href="//boards.4chan.org/v/thread/9#p9" class="quotelink">&gt;&gt;&gt;/v/9</a><br>I use linux too</blockquote>
      </div>
    </div>
  </div>
</div>
<div class="mPagelist mobile"><div class="pages">
  [<strong>1</strong>] [<a href="//find.4chan.org/?q=linux&amp;o=10">2</a>] [<a href="//find.4chan.org/?q=linux&amp;o=20">3</a>]
</div></div>
</body></html>
''';

void main() {
  test('parses opening posts and replies', () {
    final GlobalSearchPage page = parseGlobalSearchPage(_results)!;

    expect(page.posts, hasLength(2));
    expect(page.totalHits, 1234);
    expect(page.nextOffset, 10);

    final op = page.posts[0];
    expect(op.board, 'g');
    expect(op.no, 100);
    expect(op.resto, 0);
    expect(op.sub, 'Linux general');
    expect(op.name, 'Anonymous');
    expect(op.time, 1700000000);
    expect(op.tim, 1700000000123);
    expect(op.ext, '.png');
    expect(op.com, 'Which distro?<br>&gt;inb4 arch');

    // The quoted /v/ link in the comment mustn't be taken for the post.
    final reply = page.posts[1];
    expect(reply.board, 'tech');
    expect(reply.no, 205);
    expect(reply.resto, 200);
    expect(reply.sub, isNull);
    expect(reply.tim, isNull);
    expect(reply.time, 1700000500);
  });

  test('next page is the closest one after the current offset', () {
    expect(parseGlobalSearchPage(_results, offset: 10)!.nextOffset, 20);
    expect(parseGlobalSearchPage(_results, offset: 20)!.nextOffset, isNull);
  });

  test('a results page without matches is empty, not an error', () {
    final GlobalSearchPage page = parseGlobalSearchPage(
      '<form><input name="q" value="zzzz"></form><p>No results.</p>',
    )!;

    expect(page.posts, isEmpty);
    expect(page.nextOffset, isNull);
  });

  test('anything else is not a results page', () {
    expect(
      parseGlobalSearchPage(
        '<title>Just a moment...</title><div id="challenge-running"></div>',
      ),
      isNull,
    );
  });

  test('recognizes the Cloudflare challenge', () {
    expect(
      isCloudflareChallenge(
        '<title>Just a moment...</title><script src="/cdn-cgi/challenge-platform/h/b/orchestrate/chl_page/v1"></script>',
      ),
      isTrue,
    );
    expect(isCloudflareChallenge(_results), isFalse);
  });

  test('builds the find.4chan.org URL', () {
    expect(
      globalSearchUri('linux kernel').toString(),
      'https://find.4chan.org/?q=linux+kernel',
    );
    expect(
      globalSearchUri('rust', board: 'g', offset: 10).toString(),
      'https://find.4chan.org/?q=rust&b=g&o=10',
    );
  });
}
