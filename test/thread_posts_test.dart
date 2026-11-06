import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/thread/thread_posts.dart';
import 'package:flutter_test/flutter_test.dart';

/// A reply's comment quoting [ids], as 4chan marks quotes up.
String _quoting(List<int> ids) => [
  for (final int id in ids)
    '<a href="#p$id" class="quotelink">&gt;&gt;$id</a><br>',
].join();

List<int?> _numbers(Iterable<Post> posts) => [for (final p in posts) p.no];

void main() {
  group('reply tree', () {
    // 2 and 4 answer the OP; 3 answers 2; 5 quotes 1 and 3, so it hangs off
    // the last one; 6 quotes a missing post and 7 a later one.
    final List<Post> posts = [
      Post(board: 'g', no: 1),
      Post(board: 'g', no: 2, com: _quoting([1])),
      Post(board: 'g', no: 3, com: _quoting([2])),
      Post(board: 'g', no: 4, com: _quoting([1])),
      Post(board: 'g', no: 5, com: _quoting([1, 3])),
      Post(board: 'g', no: 6, com: _quoting([99])),
      Post(board: 'g', no: 7, com: _quoting([8])),
      Post(board: 'g', no: 8),
    ];

    test('hangs each reply off the earlier posts it quotes', () {
      final Map<int, List<Post>> children = buildReplyChildrenIndex(posts);
      expect(_numbers(children[1]!), [2, 4]);
      expect(_numbers(children[2]!), [3]);
      expect(_numbers(children[3]!), [5]);
      expect(children.containsKey(99), isFalse);
      expect(children.containsKey(8), isFalse);
    });

    test('hangs a reply off a post it quotes twice once', () {
      final Map<int, List<Post>> children = buildReplyChildrenIndex([
        Post(board: 'g', no: 1),
        Post(board: 'g', no: 2, com: _quoting([1, 1])),
      ]);
      expect(_numbers(children[1]!), [2]);
    });

    test('hangs a reply off every post it quotes from different branches', () {
      final Map<int, List<Post>> children = buildReplyChildrenIndex([
        Post(board: 'g', no: 1),
        Post(board: 'g', no: 2, com: _quoting([1])),
        Post(board: 'g', no: 3, com: _quoting([1])),
        Post(board: 'g', no: 4, com: _quoting([2, 3])),
      ]);
      expect(_numbers(children[2]!), [4]);
      expect(_numbers(children[3]!), [4]);
    });

    test('leaves out a post the reply is already below', () {
      final Map<int, List<Post>> children = buildReplyChildrenIndex([
        Post(board: 'g', no: 1),
        Post(board: 'g', no: 2, com: _quoting([1])),
        Post(board: 'g', no: 3, com: _quoting([2])),
        Post(board: 'g', no: 4, com: _quoting([3])),
        Post(board: 'g', no: 5, com: _quoting([2, 4, 1])),
      ]);
      expect(_numbers(children[1]!), [2]);
      expect(_numbers(children[2]!), [3]);
      expect(_numbers(children[4]!), [5]);
    });

    test('still counts a reply below every post it quotes', () {
      final Map<int, int> counts = ThreadPosts(
        board: 'g',
        number: 1,
        posts: [
          Post(board: 'g', no: 1),
          Post(board: 'g', no: 2, com: _quoting([1])),
          Post(board: 'g', no: 3, com: _quoting([2])),
          Post(board: 'g', no: 4, com: _quoting([2, 3])),
        ],
      ).replyCounts;
      expect(counts[2], 2);
      expect(counts[3], 1);
    });

    test('counts a reply reached by several routes once', () {
      final Map<int, int> counts = ThreadPosts(
        board: 'g',
        number: 1,
        posts: [
          Post(board: 'g', no: 1),
          Post(board: 'g', no: 2, com: _quoting([1])),
          Post(board: 'g', no: 3, com: _quoting([1])),
          Post(board: 'g', no: 4, com: _quoting([2, 3])),
        ],
      ).replyCounts;
      expect(counts[1], 3);
      expect(counts[2], 1);
    });

    test('finds the parent of a reply whose text starts with a digit', () {
      final Map<int, List<Post>> children = buildReplyChildrenIndex([
        Post(board: 'g', no: 1),
        Post(
          board: 'g',
          no: 2,
          com: '${_quoting([1])}4 weeks long, not on weekends.',
        ),
      ]);
      expect(_numbers(children[1]!), [2]);
    });

    test('counts and collects every reply below a post', () {
      final ThreadPosts thread = ThreadPosts(
        board: 'g',
        number: 1,
        posts: posts,
      );
      final Map<int, int> counts = thread.replyCounts;
      expect(counts[1], 4);
      expect(counts[2], 2);
      expect(counts[5], 0);
      expect(_numbers(thread.branchOf(posts[1])), [2, 3, 5]);
    });
  });
}
