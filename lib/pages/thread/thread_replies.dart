import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/constants.dart';
import 'package:flutter_chan/pages/thread/thread_page_post.dart';
import 'package:provider/provider.dart';

class ThreadReplies extends StatefulWidget {
  const ThreadReplies({
    Key? key,
    required this.post,
    required this.thread,
    required this.board,
    required this.replies,
    required this.allPosts,
  }) : super(key: key);

  final Post post;
  final int thread;
  final String board;
  final List<Post> replies;
  final List<Post> allPosts;

  @override
  State<ThreadReplies> createState() => _ThreadRepliesState();
}

class _ThreadRepliesState extends State<ThreadReplies> {
  final ScrollController scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeChanger>(context);
    final bool isDark = theme.getTheme() == ThemeData.dark();

    return Scaffold(
      backgroundColor: AppColors.pageBackground(isDark),
      appBar: CupertinoNavigationBar(
        border: Border.all(color: Colors.transparent),
        backgroundColor: AppColors.navigationBackground(isDark),
        leading: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(
              MediaQuery.textScaleFactorOf(context),
            ),
          ),
          child: Transform.translate(
            offset: const Offset(-16, 0),
            child: CupertinoNavigationBarBackButton(
              previousPageTitle: 'back',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
        middle: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(
              MediaQuery.textScaleFactorOf(context),
            ),
          ),
          child: const Text('Replies'),
        ),
      ),
      body: Scrollbar(
        controller: scrollController,
        child: ListView(
          shrinkWrap: false,
          controller: scrollController,
          children: [
            for (int i = 0; i < widget.replies.length; i++)
              ThreadPagePost(
                board: widget.board,
                thread: widget.thread,
                post: widget.replies[i],
                allPosts: widget.allPosts,
                replies: widget.replies,
                onDismiss: (i) => {},
              ),
          ],
        ),
      ),
    );
  }
}
