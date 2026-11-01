import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/API/urls.dart' as urls;
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_test/flutter_test.dart';

/// A reply's comment quoting [ids], as 4chan marks quotes up.
String _quoting(List<int> ids) => [
  for (final int id in ids)
    '<a href="#p$id" class="quotelink">&gt;&gt;$id</a><br>',
].join();

List<int?> _numbers(Iterable<Post> posts) => [for (final p in posts) p.no];

void main() {
  group('sortThreads', () {
    final List<Post> threads = [
      Post(no: 1, replies: 5, time: 300),
      Post(no: 2, replies: 50, time: 100),
      Post(no: 3, replies: 1, time: 200, sticky: 1),
      Post(no: 4, replies: 20, time: 400),
    ];

    test('sorts by the chosen key, stickies first', () {
      expect(
        _numbers(sortThreads(threads, Sort.byReplyCount, SortDirection.desc)),
        [3, 2, 4, 1],
      );
      expect(
        _numbers(sortThreads(threads, Sort.byReplyCount, SortDirection.asc)),
        [3, 1, 4, 2],
      );
      expect(
        _numbers(sortThreads(threads, Sort.byNewest, SortDirection.desc)),
        [3, 4, 1, 2],
      );
    });

    test('leaves the original list alone', () {
      sortThreads(threads, Sort.byReplyCount, SortDirection.desc);
      expect(_numbers(threads), [1, 2, 3, 4]);
    });
  });

  group('filterThreads', () {
    final List<Post> threads = [
      Post(no: 1, sub: 'Linux general', com: 'Post your desktops'),
      Post(no: 2, com: 'Tea &amp; <b>biscuits</b>'),
      Post(no: 3, name: 'linus', com: 'Nothing here'),
    ];

    test('needs every word, in any order and any case', () {
      expect(_numbers(filterThreads(threads, 'DESKTOPS linux')), [1]);
      expect(_numbers(filterThreads(threads, 'linux windows')), isEmpty);
    });

    test('searches the text without markup or escapes', () {
      expect(_numbers(filterThreads(threads, 'tea & biscuits')), [2]);
    });

    test('matches the poster name, and everything for an empty query', () {
      expect(_numbers(filterThreads(threads, 'linus')), [3]);
      expect(filterThreads(threads, '  '), threads);
    });
  });

  group('reply tree', () {
    // 2 and 4 answer the OP; 3 answers 2; 5 quotes 1 and 3, so it hangs off
    // the last one; 6 quotes a missing post and 7 a later one.
    final List<Post> posts = [
      Post(no: 1),
      Post(no: 2, com: _quoting([1])),
      Post(no: 3, com: _quoting([2])),
      Post(no: 4, com: _quoting([1])),
      Post(no: 5, com: _quoting([1, 3])),
      Post(no: 6, com: _quoting([99])),
      Post(no: 7, com: _quoting([8])),
      Post(no: 8),
    ];

    test('hangs each reply off the last earlier post it quotes', () {
      final Map<int, List<Post>> children = buildReplyChildrenIndex(posts);
      expect(_numbers(children[1]!), [2, 4]);
      expect(_numbers(children[2]!), [3]);
      expect(_numbers(children[3]!), [5]);
      expect(children.containsKey(99), isFalse);
      expect(children.containsKey(8), isFalse);
    });

    test('counts and collects every reply below a post', () {
      final Map<int, int> counts = buildReplyDescendantCountIndex(posts);
      expect(counts[1], 4);
      expect(counts[2], 2);
      expect(counts[5], 0);
      expect(_numbers(collectReplySubtree(rootPostId: 2, allPosts: posts)), [
        3,
        5,
      ]);
    });
  });

  group('Post', () {
    test('parses 4chan JSON and tells what is attached', () {
      final Post video = Post.fromJson(const {
        'no': 42,
        'tim': 1700000000000,
        'ext': '.webm',
        'w': 1280,
        'h': 720,
        'tn_w': 250,
        'tn_h': 140,
      });
      expect(video.no, 42);
      expect(video.tnW, 250);
      expect(video.hasFile, isTrue);
      expect(video.isVideo, isTrue);

      expect(Post(tim: 1, ext: '.MP4').isVideo, isTrue);
      expect(Post(tim: 1, ext: '.png').isVideo, isFalse);
      expect(Post(no: 1).hasFile, isFalse);
    });
  });

  test('urls', () {
    expect(urls.catalog('g').toString(), 'https://a.4cdn.org/g/catalog.json');
    expect(
      urls.thread('g', 123).toString(),
      'https://a.4cdn.org/g/thread/123.json',
    );
    expect(
      urls.file('wsg', 1700000000000, '.webm'),
      'https://i.4cdn.org/wsg/1700000000000.webm',
    );
    expect(
      urls.thumbnail('wsg', 1700000000000),
      'https://i.4cdn.org/wsg/1700000000000s.jpg',
    );
    expect(urls.threadPage('g', 123), 'https://boards.4chan.org/g/thread/123');
  });

  test('ApiException keeps the status for the UI', () {
    expect(const ApiException(429, 'catalog').isRateLimited, isTrue);
    expect(const ApiException(503, 'catalog').isRateLimited, isFalse);
    expect(const ApiException(503, 'catalog').toString(), contains('503'));
  });
}
