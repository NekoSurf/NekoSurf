import 'package:flutter/material.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/pages/thread/thread_rows.dart';
import 'package:flutter_test/flutter_test.dart';

/// A reply's comment quoting [ids], as 4chan marks quotes up.
String _quoting(List<int> ids) => [
  for (final int id in ids)
    '<a href="#p$id" class="quotelink">&gt;&gt;$id</a><br>',
].join();

List<int?> _numbers(List<ThreadRow> rows) => [for (final r in rows) r.post.no];

List<ThreadRow> _nested(
  List<Post> posts, {
  Set<int> collapsed = const <int>{},
  Set<int>? treePosts,
}) {
  return buildNestedRows(
    posts,
    children: buildReplyChildrenIndex([
      for (final Post post in posts)
        if (treePosts == null || treePosts.contains(post.no)) post,
    ]),
    collapsed: collapsed,
    treePosts: treePosts,
  );
}

ThreadRow _row(List<ThreadRow> rows, int no) =>
    rows.firstWhere((r) => r.post.no == no);

void main() {
  // 1 is the opening post.
  // 2 and 6 answer it, 5 answers nothing; 3 and 4 hang under 2, 7 under 3.
  final List<Post> posts = [
    Post(no: 1),
    Post(no: 2, com: _quoting([1])),
    Post(no: 3, com: _quoting([2])),
    Post(no: 4, com: _quoting([2])),
    Post(no: 5, com: 'no quote'),
    Post(no: 6, com: _quoting([1])),
    Post(no: 7, com: _quoting([3])),
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
      final List<ThreadRow> rows = _nested(posts, collapsed: {2});
      expect(_numbers(rows), [1, 2, 5, 6]);
      expect(_row(rows, 2).collapsed, isTrue);
      expect(_row(rows, 2).replyCount, 3);
      expect(_row(rows, 5).collapsed, isFalse);
    });

    test('folding inside a branch leaves the rest of it', () {
      expect(_numbers(_nested(posts, collapsed: {3})), [1, 2, 3, 4, 5, 6]);
    });

    test('folds a reply without replies, but never the opening post', () {
      final List<ThreadRow> rows = _nested(posts, collapsed: {1, 4});
      expect(_numbers(rows), [1, 2, 3, 7, 4, 5, 6]);
      expect(_row(rows, 1).collapsed, isFalse);
      expect(_row(rows, 4).collapsed, isTrue);
    });

    test('counts folded replies as read once past them', () {
      final List<ThreadRow> rows = _nested(posts, collapsed: {2});
      expect(_row(rows, 1).seen, 0);
      expect(_row(rows, 2).seen, 1);
      expect(_row(rows, 5).seen, 5);
      expect(_row(rows, 6).seen, 6);
    });

    test('the last row means every reply was read', () {
      expect(_nested(posts).last.seen, posts.length - 1);
    });

    test('leaves posts that came in later flat at the bottom', () {
      final List<Post> withNew = [
        ...posts,
        Post(no: 8, com: _quoting([3])),
        Post(no: 9, com: _quoting([8])),
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
        Post(no: 1),
        Post(no: 3, com: _quoting([2])),
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
        positions: {for (int i = 0; i < posts.length; i++) posts[i].no!: i},
      );

      // 2 as the root, with 3 and 4 as the top level below it, and 7 under 3.
      expect(_numbers(rows), [2, 3, 7, 4]);
      expect(_row(rows, 3).ancestors, isEmpty);
      expect(_row(rows, 7).ancestors, [3]);
      expect(_row(rows, 7).postIndex, 6);
    });

    test('nests as deep as people reply', () {
      final List<Post> chain = [
        Post(no: 1),
        for (int no = 2; no <= 200; no++) Post(no: no, com: _quoting([no - 1])),
      ];

      final List<ThreadRow> rows = _nested(chain);

      expect(rows, hasLength(200));
      expect(_row(rows, 200).ancestors, hasLength(198));
    });

    test('has nothing to show for an empty thread', () {
      expect(_nested(const <Post>[]), isEmpty);
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

    test('gives neighbouring levels different colours', () {
      for (int depth = 1; depth < 40; depth++) {
        expect(
          ThreadBranch.colorFor(depth),
          isNot(ThreadBranch.colorFor(depth + 1)),
        );
      }
    });

    Widget branch(List<int> ancestors, ValueChanged<int> onTapBar) {
      return MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ThreadBranch(
              ancestors: ancestors,
              previousDepth: 0,
              isDark: true,
              onTapBar: onTapBar,
              child: const SizedBox(
                width: double.infinity,
                height: 100,
                child: Text('post'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('tapping beside a reply folds the post it answers', (
      tester,
    ) async {
      final List<int> tapped = <int>[];
      await tester.pumpWidget(branch(const [1, 2], tapped.add));

      await tester.tapAt(Offset(ThreadBranch.indentFor(2) + 1, 50));

      expect(tapped, [2]);
    });

    testWidgets('leaves tapping on the post itself to the post', (
      tester,
    ) async {
      final List<int> tapped = <int>[];
      await tester.pumpWidget(branch(const [1, 2], tapped.add));

      await tester.tapAt(const Offset(300, 50));

      expect(tapped, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('has no bar at the top level', (tester) async {
      final List<int> tapped = <int>[];
      await tester.pumpWidget(branch(const [], tapped.add));

      await tester.tapAt(const Offset(2, 50));

      expect(tapped, isEmpty);
    });
  });
}
