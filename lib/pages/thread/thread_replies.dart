import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/pages/thread/thread_rows.dart';
import 'package:flutter_chan/pages/thread/thread_rows_list.dart';
import 'package:flutter_chan/widgets/dash_scaffold.dart';

/// Every reply below [post], listed the way a thread lists them.
class ThreadReplies extends StatefulWidget {
  const ThreadReplies({
    super.key,
    required this.post,
    required this.thread,
    required this.board,
    required this.allPosts,
  });

  final Post post;
  final int thread;
  final String board;
  final List<Post> allPosts;

  @override
  State<ThreadReplies> createState() => _ThreadRepliesState();
}

class _ThreadRepliesState extends State<ThreadReplies>
    with ThreadRowsList<ThreadReplies> {
  late final List<Post> _branch;
  late final Map<int, List<Post>> _children;
  late final Map<int, int> _positions;

  @override
  void initState() {
    super.initState();
    final Set<int?> replies = <int?>{
      for (final Post reply in collectReplySubtree(
        rootPostId: widget.post.no ?? 0,
        allPosts: widget.allPosts,
      ))
        reply.no,
    };
    _branch = <Post>[
      widget.post,
      for (final Post post in widget.allPosts)
        if (replies.contains(post.no)) post,
    ];
    _children = buildReplyChildrenIndex(widget.allPosts);
    _positions = <int, int>{
      for (int index = 0; index < widget.allPosts.length; index++)
        if (widget.allPosts[index].no != null)
          widget.allPosts[index].no!: index,
    };
    rebuildRows();
  }

  // The post itself is on the page before this one; its replies start here.
  @override
  List<ThreadRow> buildRows() => buildNestedRows(
    _branch,
    children: _children,
    collapsed: collapsedPosts,
    positions: _positions,
  ).skip(1).toList();

  @override
  Widget build(BuildContext context) {
    return DashBarScaffold(
      title: 'Replies to ${postLabel(widget.post.no!, widget.allPosts)}',
      body: rows.isEmpty
          ? Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                MediaQuery.paddingOf(context).top + 8,
                20,
                24,
              ),
              child: const Text(
                'No threaded replies were found for this post.',
                style: TextStyle(fontSize: 14),
              ),
            )
          : buildRowList(
              context,
              board: widget.board,
              thread: widget.thread,
              allPosts: widget.allPosts,
              rootPost: widget.post.no,
            ),
    );
  }
}
