import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/pages/thread/thread_page_post.dart';
import 'package:flutter_chan/widgets/image_viewer.dart';
import 'package:flutter_chan/widgets/webm_player.dart';
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

  late Future<List<String>> _fetchMedia;

  List<Widget> media = [];

  @override
  void initState() {
    super.initState();

    _fetchMedia = fetchMedia(widget.replies);
  }

  Future<List<String>> fetchMedia(List<Post> list) async {
    final List<String> fileNames = [];

    for (final Post post in list) {
      if (post.tim != null) {
        final String video = post.tim.toString() + post.ext.toString();

        fileNames.add(post.tim.toString() + post.ext.toString());
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

    return fileNames;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeChanger>(context);

    return FutureBuilder<List<String>>(
      future: _fetchMedia,
      builder: (context, AsyncSnapshot<List<String>> snapshot) {
        switch (snapshot.connectionState) {
          case ConnectionState.waiting:
            return const Center(child: CupertinoActivityIndicator());
          default:
            return Scaffold(
              backgroundColor: theme.getTheme() == ThemeData.light()
                  ? CupertinoColors.systemGroupedBackground
                  : CupertinoColors.black,
              extendBodyBehindAppBar: true,
              appBar: CupertinoNavigationBar(
                border: Border.all(color: Colors.transparent),
                backgroundColor: theme.getTheme() == ThemeData.light()
                    ? CupertinoColors.systemGroupedBackground.withValues(
                        alpha: 0.5,
                      )
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
      },
    );
  }
}
