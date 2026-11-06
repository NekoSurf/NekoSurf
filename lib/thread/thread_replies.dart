import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/thread/thread_posts.dart';
import 'package:flutter_chan/thread/thread_rows.dart';
import 'package:flutter_chan/thread/thread_rows_list.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';

class ThreadReplies extends StatefulWidget {
  const ThreadReplies({super.key, required this.post, required this.thread});

  final Post post;
  final ThreadPosts thread;

  @override
  State<ThreadReplies> createState() => _ThreadRepliesState();
}

class _ThreadRepliesState extends State<ThreadReplies>
    with ThreadRowsList<ThreadReplies> {
  late final List<Post> _branch = thread.branchOf(widget.post);

  @override
  void initState() {
    super.initState();
    rebuildRows();
  }

  @override
  ThreadPosts get thread => widget.thread;

  // The post itself is on the page before this one; its replies start here.
  @override
  List<ThreadRow> buildRows() =>
      layOutRows(_branch, children: thread.replies).skip(1).toList();

  @override
  Widget build(BuildContext context) {
    return DashBarScaffold(
      title: 'Replies to ${thread.labelOf(widget.post.no)}',
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
          : buildRowList(rootPost: widget.post.no),
    );
  }
}
