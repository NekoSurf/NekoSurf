import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/thread/post_hiding.dart';
import 'package:flutter_chan/thread/thread_posts.dart';
import 'package:flutter_chan/thread/thread_rows.dart';
import 'package:flutter_chan/thread/thread_rows_list.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';

/// Every post in a thread by one poster ID, in the order they were posted.
class PostsByIdPage extends StatefulWidget {
  const PostsByIdPage({super.key, required this.id, required this.thread});

  final String id;
  final ThreadPosts thread;

  @override
  State<PostsByIdPage> createState() => _PostsByIdPageState();
}

class _PostsByIdPageState extends State<PostsByIdPage>
    with ThreadRowsList<PostsByIdPage> {
  late final List<Post> _posts = thread.postsById[widget.id] ?? const <Post>[];

  @override
  void initState() {
    super.initState();
    rebuildRows();
  }

  @override
  ThreadPosts get thread => widget.thread;

  // Replies to these are elsewhere: nesting them would only leave gaps.
  @override
  ThreadLayout get layout => ThreadLayout.flat;

  // They were asked for, hidden or not.
  @override
  PostHiding get hiding => const PostHiding();

  @override
  List<ThreadRow> buildRows() => layOutRows(_posts, children: thread.replies);

  @override
  Widget build(BuildContext context) {
    return DashBarScaffold(
      title: 'ID:${widget.id}',
      subtitle: _posts.length == 1 ? '1 post' : '${_posts.length} posts',
      body: buildRowList(),
    );
  }
}
