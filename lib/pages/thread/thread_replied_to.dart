import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/pages/thread/thread_page_post.dart';
import 'package:flutter_chan/widgets/image_viewer.dart';
import 'package:flutter_chan/widgets/reload.dart';
import 'package:flutter_chan/widgets/webm_player.dart';
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

  List<Widget> media = [];
  List<String> fileName = [];

  Future<void> getMedia(Post post) async {
    if (post.tim != null) {
      final String video = post.tim.toString() + post.ext.toString();

      fileName.add(post.tim.toString() + post.ext.toString());
      media.add(
        (post.ext == '.webm' || post.ext == '.mp4')
            ? VLCPlayer(
                board: widget.board,
                video: video,
                fileName: post.filename ?? '',
              )
            : ImageViewer(
                url: 'https://i.4cdn.org/${widget.board}/$video',
                interactiveViewer: true,
              ),
      );
    }
  }

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

    return Scaffold(
      backgroundColor: theme.getTheme() == ThemeData.light()
          ? CupertinoColors.systemGroupedBackground
          : CupertinoColors.black,
      extendBodyBehindAppBar: true,
      appBar: CupertinoNavigationBar(
        border: Border.all(color: Colors.transparent),
        backgroundColor: theme.getTheme() == ThemeData.light()
            ? CupertinoColors.systemGroupedBackground.withValues(alpha: 0.7)
            : CupertinoColors.black.withOpacity(0.7),
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
                getMedia(snapshot.data ?? Post());
                return ListView(
                  shrinkWrap: false,
                  controller: scrollController,
                  children: [
                    Scrollbar(
                      controller: scrollController,
                      child: ThreadPagePost(
                        board: widget.board,
                        thread: widget.thread,
                        post: snapshot.data ?? Post(),
                        allPosts: widget.allPosts,
                        onDismiss: (i) => {},
                      ),
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
