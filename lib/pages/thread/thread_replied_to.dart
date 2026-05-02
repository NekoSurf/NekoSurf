import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/constants.dart';
import 'package:flutter_chan/pages/thread/thread_page_post.dart';
import 'package:flutter_chan/widgets/reload.dart';
import 'package:provider/provider.dart';

class ThreadRepliesTo extends StatefulWidget {
  const ThreadRepliesTo({
    Key? key,
    required this.post,
    required this.thread,
    required this.board,
    required this.allPosts,
  }) : super(key: key);

  final int post;
  final int thread;
  final String board;
  final List<Post> allPosts;

  @override
  State<ThreadRepliesTo> createState() => _ThreadRepliesToState();
}

class _ThreadRepliesToState extends State<ThreadRepliesTo> {
  final ScrollController scrollController = ScrollController();

  late Future<Post?>? _fetchPost;

  @override
  void initState() {
    super.initState();

    loadPost();
  }

  void loadPost() {
    setState(() {
      _fetchPost = fetchPost(widget.board, widget.thread, widget.post);
    });
  }

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
      body: FutureBuilder(
        future: _fetchPost,
        builder: (BuildContext context, snapshot) {
          switch (snapshot.connectionState) {
            case ConnectionState.waiting:
              return const Center(child: CupertinoActivityIndicator());
            default:
              if (snapshot.hasError) {
                return ReloadWidget(
                  onReload: () {
                    loadPost();
                  },
                );
              } else {
                return Scrollbar(
                  controller: scrollController,
                  child: ListView(
                    shrinkWrap: false,
                    controller: scrollController,
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 12,
                      bottom: MediaQuery.of(context).padding.bottom + 16,
                    ),
                    children: [
                      ThreadPagePost(
                        board: widget.board,
                        thread: widget.thread,
                        post: snapshot.data ?? Post(),
                        allPosts: widget.allPosts,
                        onDismiss: (i) => {},
                      ),
                    ],
                  ),
                );
              }
          }
        },
      ),
    );
  }
}
