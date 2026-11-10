import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/thread/thread_branch.dart';
import 'package:flutter_chan/thread/thread_posts.dart';
import 'package:flutter_chan/thread/thread_rows.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_test/flutter_test.dart';

/// A reply's comment quoting [ids], as 4chan marks quotes up.
String _quoting(List<int> ids) => [
  for (final int id in ids)
    '<a href="#p$id" class="quotelink">&gt;&gt;$id</a><br>',
].join();

List<int?> _numbers(List<ThreadRow> rows) => [for (final r in rows) r.post.no];

List<ThreadRow> _nested(
  List<Post> posts, {
  Set<String> collapsed = const <String>{},
  Map<int, int> primaryParents = const <int, int>{},
  Set<int>? treePosts,
}) {
  return buildNestedRows(
    posts,
    children: buildReplyChildrenIndex([
      for (final Post post in posts)
        if (treePosts == null || treePosts.contains(post.no)) post,
    ]),
    collapsed: collapsed,
    primaryParents: primaryParents,
    treePosts: treePosts,
  );
}

ThreadRow _row(List<ThreadRow> rows, int no) =>
    rows.firstWhere((r) => r.post.no == no);

void main() {
  // 1 is the opening post.
  // 2 and 6 answer it, 5 answers nothing; 3 and 4 hang under 2, 7 under 3.
  final List<Post> posts = [
    Post(board: 'g', no: 1),
    Post(board: 'g', no: 2, com: _quoting([1])),
    Post(board: 'g', no: 3, com: _quoting([2])),
    Post(board: 'g', no: 4, com: _quoting([2])),
    Post(board: 'g', no: 5, com: 'no quote'),
    Post(board: 'g', no: 6, com: _quoting([1])),
    Post(board: 'g', no: 7, com: _quoting([3])),
  ];

  group('buildNestedRows', () {
    test('puts each reply under the post it answers', () {
      expect(_numbers(_nested(posts)), [1, 2, 3, 7, 4, 5, 6]);
    });

    test('keeps replies to the opening post at the top level', () {
      final List<ThreadRow> rows = _nested(posts);
      expect(_row(rows, 1).ancestors, isEmpty);
      expect(_row(rows, 2).ancestors, isEmpty);
      expect(_row(rows, 5).ancestors, isEmpty);
      expect(_row(rows, 6).ancestors, isEmpty);
      expect(_row(rows, 3).ancestors, [2]);
      expect(_row(rows, 4).ancestors, [2]);
      expect(_row(rows, 7).ancestors, [2, 3]);
    });

    test('counts the replies below each post', () {
      final List<ThreadRow> rows = _nested(posts);
      expect(_row(rows, 2).replyCount, 3);
      expect(_row(rows, 3).replyCount, 1);
      expect(_row(rows, 4).replyCount, 0);
    });

    test('remembers where each post is in the thread', () {
      final List<ThreadRow> rows = _nested(posts);
      for (final ThreadRow row in rows) {
        expect(posts[row.postIndex].no, row.post.no);
      }
    });

    test('folding hides the whole branch, but not the post itself', () {
      final List<ThreadRow> rows = _nested(posts, collapsed: {'2'});
      expect(_numbers(rows), [1, 2, 5, 6]);
      expect(_row(rows, 2).collapsed, isTrue);
      expect(_row(rows, 2).replyCount, 3);
      expect(_row(rows, 5).collapsed, isFalse);
    });

    test('counts the unseen posts folded away below a post', () {
      final List<ThreadRow> rows = buildNestedRows(
        posts,
        children: buildReplyChildrenIndex(posts),
        collapsed: {'2'},
        unseen: {3, 7, 6},
      );

      expect(_row(rows, 2).newReplies, 2);
      expect(_row(rows, 6).newReplies, 0);
    });

    test("doesn't count unseen posts that aren't hidden", () {
      final List<ThreadRow> rows = buildNestedRows(
        posts,
        children: buildReplyChildrenIndex(posts),
        unseen: {3, 7},
      );

      expect(_row(rows, 2).newReplies, 0);
    });

    test('folding inside a branch leaves the rest of it', () {
      expect(_numbers(_nested(posts, collapsed: {'2/3'})), [1, 2, 3, 4, 5, 6]);
    });

    test('folds a reply without replies, but never the opening post', () {
      final List<ThreadRow> rows = _nested(posts, collapsed: {'1', '2/4'});
      expect(_numbers(rows), [1, 2, 3, 7, 4, 5, 6]);
      expect(_row(rows, 1).collapsed, isFalse);
      expect(_row(rows, 4).collapsed, isTrue);
    });

    test('names each row by the way down to it', () {
      final List<ThreadRow> rows = _nested(posts);
      expect(_row(rows, 2).path, '2');
      expect(_row(rows, 7).path, '2/3/7');
      expect(_row(rows, 7).parent, 3);
      expect(_row(rows, 2).parent, ThreadRow.topLevel);
    });

    test('leaves posts that came in later flat at the bottom', () {
      final List<Post> withNew = [
        ...posts,
        Post(board: 'g', no: 8, com: _quoting([3])),
        Post(board: 'g', no: 9, com: _quoting([8])),
      ];
      final List<ThreadRow> rows = _nested(
        withNew,
        treePosts: {1, 2, 3, 4, 5, 6, 7},
      );
      expect(_numbers(rows), [1, 2, 3, 7, 4, 5, 6, 8, 9]);
      expect(_row(rows, 8).ancestors, isEmpty);
      expect(_row(rows, 9).ancestors, isEmpty);
      // The counts match what's actually below the post.
      expect(_row(rows, 3).replyCount, 1);
    });

    test('a reply whose parent was deleted moves to the top level', () {
      final List<ThreadRow> rows = _nested([
        Post(board: 'g', no: 1),
        Post(board: 'g', no: 3, com: _quoting([2])),
      ]);
      expect(_numbers(rows), [1, 3]);
      expect(_row(rows, 3).ancestors, isEmpty);
    });

    test('shows the count passed for the opening post', () {
      final List<ThreadRow> rows = buildNestedRows(
        posts,
        children: buildReplyChildrenIndex(posts),
        opReplyCount: 42,
      );
      expect(_row(rows, 1).replyCount, 42);
    });

    test('keeps a part of a thread where it is in the thread', () {
      final List<ThreadRow> rows = buildNestedRows(
        [posts[1], posts[2], posts[3], posts[6]],
        children: buildReplyChildrenIndex(posts),
        positions: {for (int i = 0; i < posts.length; i++) posts[i].no: i},
      );

      // 2 as the root, with 3 and 4 as the top level below it, and 7 under 3.
      expect(_numbers(rows), [2, 3, 7, 4]);
      expect(_row(rows, 3).ancestors, isEmpty);
      expect(_row(rows, 7).ancestors, [3]);
      expect(_row(rows, 7).postIndex, 6);
    });

    test('nests as deep as people reply', () {
      final List<Post> chain = [
        Post(board: 'g', no: 1),
        for (int no = 2; no <= 200; no++)
          Post(board: 'g', no: no, com: _quoting([no - 1])),
      ];

      final List<ThreadRow> rows = _nested(chain);

      expect(rows, hasLength(200));
      expect(_row(rows, 200).ancestors, hasLength(198));
    });

    group('a reply quoting several posts', () {
      // 1 is the opening post. 4 quotes 2 and 3, 5 quotes 2 twice, and 6 quotes
      // both 2 and 5, which is itself below 2.
      final List<Post> quoting = [
        Post(board: 'g', no: 1),
        Post(board: 'g', no: 2, com: _quoting([1])),
        Post(board: 'g', no: 3, com: _quoting([1])),
        Post(board: 'g', no: 4, com: _quoting([2, 3])),
        Post(board: 'g', no: 5, com: _quoting([2, 2])),
        Post(board: 'g', no: 6, com: _quoting([2, 5])),
      ];

      List<ThreadRow> rowsOf({Set<String> collapsed = const <String>{}}) =>
          _nested(quoting, collapsed: collapsed);

      ThreadRow at(List<ThreadRow> rows, String path) =>
          rows.firstWhere((r) => r.path == path);

      test('shows under every one of them', () {
        final List<ThreadRow> rows = rowsOf();

        expect(_numbers(rows), [1, 2, 4, 5, 6, 3, 4]);
        expect(at(rows, '2/4').ancestors, [2]);
        expect(at(rows, '3/4').ancestors, [3]);
      });

      test('shows once under a post it quotes twice', () {
        expect(rowsOf().where((r) => r.post.no == 5), hasLength(1));
      });

      test("doesn't repeat under a post it's already below another way", () {
        final List<ThreadRow> rows = rowsOf();

        expect(at(rows, '2/5/6').ancestors, [2, 5]);
        expect(rows.where((r) => r.path == '2/6'), isEmpty);
      });

      test('is simply repeated if short', () {
        expect(rowsOf().where((r) => r.isPreview), isEmpty);
      });

      test('counts as one reply, however many times it shows', () {
        final List<Post> posts = [
          Post(board: 'g', no: 1),
          Post(board: 'g', no: 2, com: _quoting([1])),
          Post(board: 'g', no: 3, com: _quoting([2])),
          Post(board: 'g', no: 4, com: _quoting([2])),
          Post(board: 'g', no: 5, com: _quoting([3, 4])),
        ];
        final List<ThreadRow> rows = _nested(posts);

        expect(_numbers(rows), [1, 2, 3, 5, 4, 5]);
        expect(_row(rows, 2).replyCount, 3);
      });

      test('shows at the top level too if it quotes the opening post', () {
        final List<Post> posts = [
          Post(board: 'g', no: 1),
          Post(board: 'g', no: 2, com: 'no quote'),
          Post(board: 'g', no: 3, com: _quoting([2, 1])),
        ];
        final List<ThreadRow> rows = _nested(posts);

        expect(_numbers(rows), [1, 2, 3, 3]);
        expect(at(rows, '2/3').ancestors, [2]);
        expect(at(rows, '3').ancestors, isEmpty);
      });

      test('stays below a reply to the opening post it also quotes', () {
        final List<ThreadRow> rows = _nested([
          Post(board: 'g', no: 1),
          Post(board: 'g', no: 2, com: _quoting([1])),
          Post(board: 'g', no: 3, com: _quoting([2, 1])),
        ]);

        expect(_numbers(rows), [1, 2, 3]);
        expect(at(rows, '2/3').ancestors, [2]);
      });

      test('folds in one place, leaving the other', () {
        final List<ThreadRow> rows = rowsOf(collapsed: {'2/4'});

        expect(at(rows, '2/4').collapsed, isTrue);
        expect(at(rows, '3/4').collapsed, isFalse);
      });

      test('folding hides its replies there', () {
        expect(_numbers(rowsOf(collapsed: {'2'})), [1, 2, 3, 4]);
      });

      test('a part of a thread keeps a reply that also quotes outside it', () {
        final List<Post> posts = [
          Post(board: 'g', no: 1),
          Post(board: 'g', no: 2, com: _quoting([1])),
          Post(board: 'g', no: 3, com: _quoting([1])),
          Post(board: 'g', no: 4, com: _quoting([2, 3])),
        ];
        final List<ThreadRow> rows = buildNestedRows([
          posts[1],
          posts[3],
        ], children: buildReplyChildrenIndex(posts));

        expect(_numbers(rows), [2, 4]);
      });

      group('with replies below it', () {
        // 4 quotes 2 and 3, and 5 and 6 answer it.
        final List<Post> branching = [
          Post(board: 'g', no: 1),
          Post(board: 'g', no: 2, com: _quoting([1])),
          Post(board: 'g', no: 3, com: _quoting([1])),
          Post(board: 'g', no: 4, com: _quoting([2, 3])),
          Post(board: 'g', no: 5, com: _quoting([4])),
          Post(board: 'g', no: 6, com: _quoting([4])),
        ];

        test('is shown in full under the first, a preview under the rest', () {
          final List<ThreadRow> rows = _nested(branching);

          expect(_numbers(rows), [1, 2, 4, 5, 6, 3, 4]);
          expect(at(rows, '2/4').isPreview, isFalse);
          expect(at(rows, '3/4').isPreview, isTrue);
        });

        test('its preview still counts its replies', () {
          expect(at(_nested(branching), '3/4').replyCount, 2);
        });

        test('moves to where it was chosen', () {
          final List<ThreadRow> rows = _nested(
            branching,
            primaryParents: {4: 3},
          );

          expect(_numbers(rows), [1, 2, 4, 3, 4, 5, 6]);
          expect(at(rows, '2/4').isPreview, isTrue);
          expect(at(rows, '3/4').isPreview, isFalse);
        });

        test('stays where it is while folded there', () {
          final List<ThreadRow> rows = _nested(branching, collapsed: {'2/4'});

          expect(_numbers(rows), [1, 2, 4, 3, 4]);
          expect(at(rows, '2/4').collapsed, isTrue);
          expect(at(rows, '3/4').isPreview, isTrue);
        });

        test("a preview doesn't fold", () {
          final List<ThreadRow> rows = _nested(branching, collapsed: {'3/4'});

          expect(at(rows, '3/4').collapsed, isFalse);
          expect(at(rows, '3/4').isPreview, isTrue);
        });
      });

      test('with an image is a preview under the rest', () {
        final List<Post> posts = [
          Post(board: 'g', no: 1),
          Post(board: 'g', no: 2, com: _quoting([1])),
          Post(board: 'g', no: 3, com: _quoting([1])),
          Post(board: 'g', no: 4, com: _quoting([2, 3]), tim: 1, ext: '.jpg'),
        ];
        final List<ThreadRow> rows = _nested(posts);

        expect(at(rows, '2/4').isPreview, isFalse);
        expect(at(rows, '3/4').isPreview, isTrue);
      });

      test('with a lot of text is a preview under the rest', () {
        final List<Post> posts = [
          Post(board: 'g', no: 1),
          Post(board: 'g', no: 2, com: _quoting([1])),
          Post(board: 'g', no: 3, com: _quoting([1])),
          Post(
            board: 'g',
            no: 4,
            com: '${_quoting([2, 3])}${'A long line. ' * 80}',
          ),
        ];
        final List<ThreadRow> rows = _nested(posts);

        expect(at(rows, '3/4').isPreview, isTrue);
      });

      test("can't multiply out of hand, and reaches every post", () {
        // Pairs of posts that each quote both of the pair before: repeating
        // what's below them would double the rows with every pair.
        final List<Post> layers = [
          Post(board: 'g', no: 1),
          Post(board: 'g', no: 2, com: _quoting([1])),
          Post(board: 'g', no: 3, com: _quoting([1])),
          for (int pair = 2; pair < 150; pair++) ...[
            Post(
              board: 'g',
              no: pair * 2,
              com: _quoting([pair * 2 - 2, pair * 2 - 1]),
            ),
            Post(
              board: 'g',
              no: pair * 2 + 1,
              com: _quoting([pair * 2 - 2, pair * 2 - 1]),
            ),
          ],
        ];

        final List<ThreadRow> rows = _nested(layers);

        expect(rows.length, lessThan(layers.length * 3));
        expect(
          rows.map((r) => r.post.no).toSet(),
          layers.map((p) => p.no).toSet(),
        );
      });
    });

    test('has nothing to show for an empty thread', () {
      expect(_nested(const <Post>[]), isEmpty);
    });
  });

  group('buildFlatRows', () {
    final Map<int, int> counts = ThreadPosts(
      board: 'g',
      number: 1,
      posts: posts,
    ).replyCounts;

    test('lists every post once, in the order it was posted', () {
      final List<ThreadRow> rows = buildFlatRows(posts, replyCounts: counts);

      expect(_numbers(rows), [1, 2, 3, 4, 5, 6, 7]);
      expect(rows.every((r) => r.ancestors.isEmpty), isTrue);
      expect(rows.map((r) => r.path).toSet(), hasLength(posts.length));
    });

    test('counts the replies below each post', () {
      final List<ThreadRow> rows = buildFlatRows(posts, replyCounts: counts);

      expect(_row(rows, 2).replyCount, 3);
      expect(_row(rows, 7).replyCount, 0);
    });

    test('folds a post on its own, but not the first one', () {
      final List<ThreadRow> rows = buildFlatRows(
        posts,
        replyCounts: counts,
        collapsed: {'1', '3'},
      );

      expect(_numbers(rows), [1, 2, 3, 4, 5, 6, 7]);
      expect(_row(rows, 1).collapsed, isFalse);
      expect(_row(rows, 3).collapsed, isTrue);
    });

    test('keeps a part of a thread where it is in the thread', () {
      final List<ThreadRow> rows = buildFlatRows(
        [posts[1], posts[6]],
        replyCounts: counts,
        positions: {for (int i = 0; i < posts.length; i++) posts[i].no: i},
      );

      expect(_row(rows, 7).postIndex, 6);
    });
  });

  group('ThreadBranch', () {
    test('moves each level less than the one before', () {
      expect(ThreadBranch.indentFor(0), 0);
      double last = 0;
      double lastStep = double.infinity;
      for (int depth = 1; depth <= 30; depth++) {
        final double indent = ThreadBranch.indentFor(depth);
        final double step = indent - last;
        expect(step, greaterThan(0));
        expect(step, lessThanOrEqualTo(lastStep));
        last = indent;
        lastStep = step;
      }
      // Still most of a phone's width left, thirty replies deep.
      expect(ThreadBranch.indentFor(30), lessThan(120));
    });

    test('gives neighbouring levels different colours, in every theme', () {
      for (final ThemeColor theme in ThemeColor.values) {
        for (int depth = 1; depth < 40; depth++) {
          expect(
            ThreadBranch.colorFor(depth, theme),
            isNot(ThreadBranch.colorFor(depth + 1, theme)),
            reason: theme.name,
          );
        }
      }
    });
  });
}
