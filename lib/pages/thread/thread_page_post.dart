import 'dart:math';

import 'package:country_flags/country_flags.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/pages/replies_row.dart';
import 'package:flutter_chan/pages/thread/thread_media_viewer_page.dart';
import 'package:flutter_chan/pages/thread/thread_post_comment.dart';
import 'package:flutter_chan/pages/thread/thread_replies.dart';
import 'package:flutter_chan/services/string.dart';
import 'package:flutter_chan/widgets/feed_player_pool.dart';
import 'package:flutter_chan/widgets/feed_video_player.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class ThreadPagePost extends StatefulWidget {
  const ThreadPagePost({
    Key? key,
    required this.board,
    required this.post,
    required this.thread,
    required this.allPosts,
    required this.onDismiss,
    this.replies,
    this.replyCount = 0,
    this.eagerVideoInit = false,
    this.playerPool,
  }) : super(key: key);

  final String board;
  final int thread;
  final Post post;
  final List<Post> allPosts;
  final Function(int? postId) onDismiss;
  final List<Post>? replies;
  final int replyCount;
  final bool eagerVideoInit;
  final FeedPlayerPool? playerPool;

  static String formatBytes(int bytes, int decimals) {
    if (bytes <= 0) {
      return '0 B';
    }
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
    final i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  @override
  State<ThreadPagePost> createState() => _ThreadPagePostState();
}

class _ThreadPagePostState extends State<ThreadPagePost> {
  Future<void> _openReplies() async {
    final focusedPostId = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (context) => ThreadReplies(
          post: widget.post,
          thread: widget.thread,
          board: widget.board,
          allPosts: widget.allPosts,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    widget.onDismiss(focusedPostId);
  }

  String _thumbnailUrl() {
    return 'https://i.4cdn.org/${widget.board}/${widget.post.tim}s.jpg';
  }

  String _fullMediaUrl() {
    return 'https://i.4cdn.org/${widget.board}/${widget.post.tim}${widget.post.ext}';
  }

  bool _isVideoPost() {
    final ext = widget.post.ext?.toLowerCase();
    return ext == '.webm' || ext == '.mp4';
  }

  bool _hasRenderableMedia() {
    return widget.post.tim != null && widget.post.ext != null;
  }

  Future<void> _openMediaViewer(List<Post> allPosts, Post thisPost) async {
    final mediaPosts = allPosts
        .where((p) => p.tim != null && p.ext != null)
        .toList();
    final index = mediaPosts.indexWhere((p) => p.no == thisPost.no);
    if (index < 0) {
      return;
    }
    final focusedPostId = await Navigator.of(context).push<int>(
      ThreadMediaViewerRoute(
        mediaPosts: mediaPosts,
        initialIndex: index,
        board: widget.board,
        thread: widget.thread,
      ),
    );
    if (!mounted) {
      return;
    }
    widget.onDismiss(focusedPostId);
  }

  double _mediaAspectRatio() {
    final int width = widget.post.w ?? widget.post.tnW ?? 1;
    final int height = widget.post.h ?? widget.post.tnH ?? 1;
    final ratio = width / max(height, 1);
    return ratio.clamp(0.65, 1.8);
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.22),
      child: const Center(child: CupertinoActivityIndicator(radius: 12)),
    );
  }

  Widget _buildInlineImageMedia() {
    final imageMedia = AspectRatio(
      aspectRatio: _mediaAspectRatio(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              _thumbnailUrl(),
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) {
                  return child;
                }

                return Stack(
                  fit: StackFit.expand,
                  children: [child, _buildLoadingOverlay()],
                );
              },
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              _fullMediaUrl(),
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) {
                  return child;
                }

                return Stack(
                  fit: StackFit.expand,
                  children: [child, _buildLoadingOverlay()],
                );
              },
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded) {
                  return child;
                }

                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  child: child,
                );
              },
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: () =>
          _openMediaViewer(widget.replies ?? widget.allPosts, widget.post),
      child: imageMedia,
    );
  }

  Widget _buildInlineVideoMedia() {
    if (!_hasRenderableMedia()) {
      return const SizedBox.shrink();
    }
    final mediaId = widget.post.tim;
    if (mediaId == null) {
      return _buildInlineImageMedia();
    }
    final fileName = '$mediaId${widget.post.ext ?? '.webm'}';
    final mediaUrl = 'https://i.4cdn.org/${widget.board}/$fileName';
    final itemKey = widget.post.no ?? mediaId;

    try {
      return GestureDetector(
        onTap: () =>
            _openMediaViewer(widget.replies ?? widget.allPosts, widget.post),
        child: FeedVideoPlayer(
          key: ValueKey('feed-player-${widget.board}-$itemKey'),
          videoUrl: mediaUrl,
          thumbnailUrl: _thumbnailUrl(),
          aspectRatio: _mediaAspectRatio(),
          eagerInitialize: widget.eagerVideoInit,
          pool: widget.playerPool,
        ),
      );
    } catch (_) {
      return _buildInlineImageMedia();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeChanger>(context);
    final bool isDark = theme.getTheme() == ThemeData.dark();
    final bool hasMedia = _hasRenderableMedia();

    final Color primaryText = isDark ? Colors.white : const Color(0xFF121417);
    final Color secondaryText = isDark
        ? CupertinoColors.systemGrey
        : const Color(0xFF5B6470);
    final Color cardColor = isDark
        ? const Color(0xFF13161B)
        : const Color(0xFFFFFFFF);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? CupertinoColors.systemGrey.withValues(alpha: 0.25)
                    : const Color(0x14000000),
                width: 1,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x12000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: CupertinoColors.activeBlue.withValues(
                          alpha: 0.2,
                        ),
                        child: Text(
                          (widget.post.name ?? 'Anonymous')
                              .trim()
                              .characters
                              .first
                              .toUpperCase(),
                          style: const TextStyle(
                            color: CupertinoColors.activeBlue,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.post.name ?? 'Anonymous',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: primaryText,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: CupertinoColors.systemFill
                                        .resolveFrom(context),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    'No.${widget.post.no}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (widget.post.country != null &&
                                    CountryFlag.fromCountryCode(
                                          widget.post.country!,
                                        ) !=
                                        null)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: SizedBox(
                                      width: 16,
                                      height: 11,
                                      child: CountryFlag.fromCountryCode(
                                        widget.post.country!,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            Text(
                              DateFormat('kk:mm - dd.MM.y').format(
                                DateTime.fromMillisecondsSinceEpoch(
                                  widget.post.time! * 1000,
                                ),
                              ),
                              style: TextStyle(
                                fontSize: 11,
                                color: secondaryText,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (widget.post.sub != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      unescape(cleanTags(widget.post.sub ?? '')),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: primaryText,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (hasMedia) ...[
                    const SizedBox(height: 10),
                    if (_isVideoPost())
                      _buildInlineVideoMedia()
                    else
                      _buildInlineImageMedia(),
                  ],
                  if (widget.post.com != null) ...[
                    const SizedBox(height: 10),
                    ThreadPostComment(
                      com: widget.post.com ?? '',
                      board: widget.board,
                      thread: widget.thread,
                      allPosts: widget.allPosts,
                    ),
                  ],
                  if (widget.replyCount > 0)
                    Column(
                      children: [
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: _openReplies,
                          child: RepliesRow(
                            replies: widget.replyCount,
                            showImageReplies: false,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
