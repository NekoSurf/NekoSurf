import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chan/chan/api.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/thread/thread_page_post.dart';
import 'package:flutter_chan/thread/thread_posts.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';
import 'package:flutter_chan/ui/reload.dart';

class QuotedPostPage extends StatefulWidget {
  const QuotedPostPage({super.key, required this.post, required this.thread});

  final int post;
  final ThreadPosts thread;

  @override
  State<QuotedPostPage> createState() => _QuotedPostPageState();
}

class _QuotedPostPageState extends State<QuotedPostPage> {
  late Future<Post?> _post = _loadPost();

  // The quoted post is almost always in the thread that's already loaded; only
  // fall back to downloading the thread again when it isn't.
  Future<Post?> _loadPost() {
    final Post? loaded = widget.thread.post(widget.post);
    return loaded != null
        ? SynchronousFuture<Post?>(loaded)
        : fetchPost(widget.thread.board, widget.thread.number, widget.post);
  }

  void _reload() => setState(() => _post = _loadPost());

  @override
  Widget build(BuildContext context) {
    return DashBarScaffold(
      title: 'Replies to ${widget.thread.labelOf(widget.post)}',
      body: FutureBuilder(
        future: _post,
        builder: (BuildContext context, snapshot) {
          switch (snapshot.connectionState) {
            case ConnectionState.waiting:
              return const Center(child: CupertinoActivityIndicator());
            default:
              if (snapshot.hasError) {
                return ReloadWidget.forError(snapshot.error, onReload: _reload);
              } else if (snapshot.data == null) {
                return ReloadWidget(
                  onReload: _reload,
                  icon: CupertinoIcons.question_circle,
                  title: 'Post not found',
                  message: 'It was deleted, or is no longer in this thread.',
                );
              } else {
                // Scrolls for a long post, or a tall video under its text.
                return ListView(
                  padding: EdgeInsets.only(
                    top: MediaQuery.paddingOf(context).top + 8,
                    bottom: MediaQuery.paddingOf(context).bottom + 8,
                  ),
                  children: [
                    ThreadPagePost(thread: widget.thread, post: snapshot.data!),
                  ],
                );
              }
          }
        },
      ),
    );
  }
}
