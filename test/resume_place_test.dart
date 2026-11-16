import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/history/thread_memory.dart';
import 'package:flutter_chan/thread/resume_place.dart';
import 'package:flutter_chan/thread/thread_posts.dart';
import 'package:flutter_chan/thread/thread_rows.dart';
import 'package:flutter_test/flutter_test.dart';

String _quoting(int id) =>
    '<a href="#p$id" class="quotelink">&gt;&gt;$id</a><br>';

List<ThreadRow> _rows(List<Post> posts, {List<int> batches = const []}) =>
    buildNestedRows(
      posts,
      children: buildReplyChildrenIndex(posts),
      batches: batches,
    );

({int row, double alignment})? _resume(
  List<ThreadRow> rows, {
  int? post,
  String? path,
  double? alignment,
  List<int> batches = const [],
}) => resumePlace(
  ThreadMemory(
    topPost: post,
    topPath: path,
    topAlignment: alignment,
    batches: batches,
  ),
  rows,
  belowHeader: 0.1,
);

void main() {
  // 1 is the opening post; 2 and 3 answer it; 4 answers 2 and came later.
  final List<Post> posts = <Post>[
    Post(board: 'g', no: 1),
    Post(board: 'g', no: 2, com: _quoting(1)),
    Post(board: 'g', no: 3, com: _quoting(1)),
    Post(board: 'g', no: 4, com: _quoting(2)),
  ];
  final List<Post> more = <Post>[
    ...posts,
    Post(board: 'g', no: 5, com: _quoting(3)),
  ];

  test('opens at the row left, where it is still listed', () {
    final List<ThreadRow> rows = _rows(posts);
    final ({int row, double alignment})? place = _resume(
      rows,
      post: 3,
      path: '3',
      alignment: 0.3,
    );
    expect(rows[place!.row].path, '3');
    expect(place.alignment, 0.3);
  });

  test('a reply left at the bottom is found there again', () {
    // 4 came while away, and was read at the bottom.
    final List<ThreadRow> left = _rows(posts, batches: [3]);
    expect(left.last.path, 'new:2/4');

    // Nothing new: it's listed just the same.
    final List<ThreadRow> rows = _rows(posts, batches: [3, 4]);
    final ({int row, double alignment})? place = _resume(
      rows,
      post: 4,
      path: 'new:2/4',
      alignment: -0.2,
      batches: [3, 4],
    );
    expect(rows[place!.row].path, 'new:2/4');
    expect(place.alignment, -0.2);
  });

  test('once what was at the bottom is in the thread, opens at the new', () {
    // 4 was read, and 5 came since: 4 is in the thread now.
    final List<ThreadRow> rows = _rows(more, batches: [4]);
    expect(rows.where((r) => r.path == 'new:2/4'), isEmpty);
    final ({int row, double alignment})? place = _resume(
      rows,
      post: 4,
      path: 'new:2/4',
      alignment: 0,
      batches: [4],
    );
    // At 5, with the post it answers above it.
    expect(rows[place!.row].isContext, isTrue);
    expect(rows[place.row + 1].post.no, 5);
    expect(place.alignment, 0.1);
  });

  test('opens at the end when nothing new is shown', () {
    final List<ThreadRow> rows = _rows(posts, batches: [4]);
    final ({int row, double alignment})? place = _resume(
      rows,
      post: 4,
      path: 'new:2/4',
      alignment: 0,
      batches: [4],
    );
    expect(place?.row, rows.length - 1);
  });

  test('a post that is gone opens at the nearest one, not the top', () {
    final List<ThreadRow> rows = _rows(<Post>[posts[0], posts[1], posts[3]]);
    final ({int row, double alignment})? place = _resume(
      rows,
      post: 3,
      path: '3',
      alignment: 0.5,
    );
    expect(rows[place!.row].post.no, 2);
  });

  test('one gone from the bottom opens at its neighbour there', () {
    // 5 was deleted; 4 and 6 are still at the bottom.
    final List<Post> withSix = <Post>[
      ...posts,
      Post(board: 'g', no: 6, com: _quoting(3)),
    ];
    final List<ThreadRow> rows = _rows(withSix, batches: [3, 6]);
    final ({int row, double alignment})? place = _resume(
      rows,
      post: 5,
      path: 'new:3/5',
      alignment: 0,
      batches: [3, 6],
    );
    expect(rows[place!.row].path, 'new:2/4');
  });

  test('nothing remembered opens at the top', () {
    expect(resumePlace(null, _rows(posts), belowHeader: 0.1), isNull);
  });
}
