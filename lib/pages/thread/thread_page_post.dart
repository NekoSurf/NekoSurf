import 'dart:math';

import 'package:country_flags/country_flags.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/urls.dart' as urls;
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:flutter_chan/pages/replies_row.dart';
import 'package:flutter_chan/pages/thread/thread_media_viewer_page.dart';
import 'package:flutter_chan/pages/thread/thread_post_comment.dart';
import 'package:flutter_chan/pages/thread/thread_replies.dart';
import 'package:flutter_chan/services/image_cache.dart';
import 'package:flutter_chan/services/string.dart';
import 'package:flutter_chan/widgets/feed_video_player.dart';
import 'package:flutter_chan/widgets/image_viewer.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class ThreadPagePost extends StatefulWidget {
  const ThreadPagePost({
    super.key,
    required this.board,
    required this.post,
    required this.thread,
    required this.allPosts,
    required this.onDismiss,
    this.replies,
    this.replyCount = 0,
    this.preloadVideo = false,
  });

  final String board;
  final int thread;
  final Post post;
  final List<Post> allPosts;
  final Function(int? postId) onDismiss;
  final List<Post>? replies;
  final int replyCount;

  /// Download the video ahead of time, as it's about to scroll into view.
  final bool preloadVideo;

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
  final GlobalKey _videoBoxKey = GlobalKey();

  /// Where the viewer zooms the video from: its inline box, below the
  /// thread's title bar (the body's top padding).
  MediaZoomOrigin? _zoomOrigin() {
    final int? width = widget.post.w;
    final int? height = widget.post.h;
    if (width == null || height == null || height <= 0) {
      return null;
    }
    return MediaZoomOrigin(
      boxKey: _videoBoxKey,
      postId: widget.post.no,
      clipTop: MediaQuery.paddingOf(context).top,
      aspectRatio: width / height,
    );
  }

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

  String _thumbnailUrl() => urls.thumbnail(widget.board, widget.post.tim);

  String _fullMediaUrl() =>
      urls.file(widget.board, widget.post.tim, widget.post.ext);

  Future<void> _openMediaViewer(
    List<Post> allPosts,
    Post thisPost, {
    MediaZoomOrigin? origin,
  }) async {
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
        origin: origin,
      ),
    );
    // Only scroll the thread to a post swiped to in the viewer: scrolling
    // now would also move the video zooming back into this post.
    if (!mounted || focusedPostId == thisPost.no) {
      return;
    }
    widget.onDismiss(focusedPostId);
  }

  /// The inline card's width in physical pixels, capped at the original's.
  int? _inlineDecodeWidth(BuildContext context) {
    final double target =
        MediaQuery.sizeOf(context).width *
        MediaQuery.devicePixelRatioOf(context);
    final int? original = widget.post.w;
    return original == null ? target.round() : min(original, target.round());
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
            child: Image(
              image: thumbnailImage(_thumbnailUrl()),
              fit: BoxFit.cover,
              errorBuilder: imageErrorPlaceholder,
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
            child: Image(
              // Decode at display size: a 4000px original fills ~48 MB once
              // decoded, for a card about 400pt wide.
              image: ResizeImage.resizeIfNeeded(
                _inlineDecodeWidth(context),
                null,
                fullImage(_fullMediaUrl()),
              ),
              fit: BoxFit.cover,
              // The thumbnail underneath stays visible if this fails.
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
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
    if (!widget.post.hasFile) {
      return const SizedBox.shrink();
    }
    final mediaId = widget.post.tim;
    if (mediaId == null) {
      return _buildInlineImageMedia();
    }
    final mediaUrl = urls.file(
      widget.board,
      mediaId,
      widget.post.ext ?? '.webm',
    );
    final itemKey = widget.post.no ?? mediaId;

    try {
      return FeedVideoPlayer(
        key: ValueKey('feed-player-${widget.board}-$itemKey'),
        videoUrl: mediaUrl,
        thumbnailUrl: _thumbnailUrl(),
        aspectRatio: _mediaAspectRatio(),
        videoWidth: widget.post.w,
        videoHeight: widget.post.h,
        preload: widget.preloadVideo,
        startMuted: Provider.of<SettingsProvider>(
          context,
        ).getFeedVideosStartMuted(),
        boxKey: _videoBoxKey,
        onTap: () => _openMediaViewer(
          widget.replies ?? widget.allPosts,
          widget.post,
          origin: _zoomOrigin(),
        ),
      );
    } catch (_) {
      return _buildInlineImageMedia();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeChanger>(context);
    final bool isDark = theme.isDark;
    final bool hasMedia = widget.post.hasFile;

    final Color primaryText = DashColors.text(isDark);
    final Color secondaryText = DashColors.muted(isDark);
    final Color cardColor = DashColors.card(isDark);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: DashColors.border(isDark)),
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
                        backgroundColor: DashColors.accent.withValues(
                          alpha: 0.2,
                        ),
                        child: Text(
                          (widget.post.name ?? 'Anonymous')
                              .trim()
                              .characters
                              .first
                              .toUpperCase(),
                          style: const TextStyle(
                            color: DashColors.accent,
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
                                if (widget.post.country != null)
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
                    if (widget.post.isVideo)
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
