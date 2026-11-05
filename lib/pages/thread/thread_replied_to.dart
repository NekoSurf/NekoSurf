import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/pages/thread/thread_page_post.dart';
import 'package:flutter_chan/pages/thread/thread_rows.dart';
import 'package:flutter_chan/widgets/dash_scaffold.dart';
import 'package:flutter_chan/widgets/reload.dart';

class ThreadRepliesTo extends StatefulWidget {
  const ThreadRepliesTo({
    super.key,
    required this.post,
    required this.thread,
    required this.board,
    required this.allPosts,
  });

  final int post;
  final int thread;
  final String board;
  final List<Post> allPosts;

  @override
  State<ThreadRepliesTo> createState() => _ThreadRepliesToState();
}

class _ThreadRepliesToState extends State<ThreadRepliesTo> {
  late Future<Post?>? _fetchPost;

  @override
  void initState() {
    super.initState();

    loadPost();
  }

  void loadPost() {
    // The quoted post is almost always in the thread that's already loaded;
    // only fall back to downloading the thread again when it isn't.
    Post? loaded;
    for (final Post candidate in widget.allPosts) {
      if (candidate.no == widget.post) {
        loaded = candidate;
        break;
      }
    }

    setState(() {
      _fetchPost = loaded != null
          ? SynchronousFuture<Post?>(loaded)
          : fetchPost(widget.board, widget.thread, widget.post);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DashBarScaffold(
      title: 'Replies to ${postLabel(widget.post, widget.allPosts)}',
      body: FutureBuilder(
        future: _fetchPost,
        builder: (BuildContext context, snapshot) {
          switch (snapshot.connectionState) {
            case ConnectionState.waiting:
              return const Center(child: CupertinoActivityIndicator());
            default:
              if (snapshot.hasError) {
                return ReloadWidget.forError(
                  snapshot.error,
                  onReload: () {
                    loadPost();
                  },
                );
              } else if (snapshot.data == null) {
                return ReloadWidget(
                  onReload: loadPost,
                  icon: CupertinoIcons.question_circle,
                  title: 'Post not found',
                  message: 'It was deleted, or is no longer in this thread.',
                );
              } else {
                final Post post = snapshot.data!;
                final int number = widget.allPosts.indexWhere(
                  (candidate) => candidate.no == post.no,
                );
                // Scrolls for a long post, or a tall video under its text.
                return ListView(
                  padding: EdgeInsets.only(
                    top: MediaQuery.paddingOf(context).top + 8,
                    bottom: MediaQuery.paddingOf(context).bottom + 8,
                  ),
                  children: [
                    ThreadPagePost(
                      board: widget.board,
                      thread: widget.thread,
                      post: post,
                      allPosts: widget.allPosts,
                      number: number < 0 ? null : number,
                      onDismiss: (i) => {},
                    ),
                  ],
                );
              }
          }
        },
      ),
    );
  }
}
