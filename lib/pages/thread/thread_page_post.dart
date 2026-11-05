import 'dart:math';

import 'package:country_flags/country_flags.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/urls.dart' as urls;
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:flutter_chan/pages/thread/thread_media_viewer_page.dart';
import 'package:flutter_chan/pages/thread/thread_post_comment.dart';
import 'package:flutter_chan/pages/thread/thread_replies.dart';
import 'package:flutter_chan/services/back_swipe_route.dart';
import 'package:flutter_chan/services/image_cache.dart';
import 'package:flutter_chan/services/string.dart';
import 'package:flutter_chan/widgets/feed_video_player.dart';
import 'package:flutter_chan/widgets/image_viewer.dart';
import 'package:flutter_chan/widgets/media_video.dart';
import 'package:flutter_chan/widgets/spoiler_cover.dart';
import 'package:provider/provider.dart';

/// A post as a row: a one-line header, then its text, then its image or
/// video. Tapping it folds it down to its header, along with any replies
/// listed below it.
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
    this.onToggleFold,
    this.folded = false,
    this.isPreview = false,
    this.countOpensReplies = false,
    this.newReplies = 0,
    this.onTapQuote,
    this.repliedTo,
    this.number,
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

  /// It can fold: without this, its count opens its replies on their own page.
  final VoidCallback? onToggleFold;
  final bool folded;

  /// Shown in full elsewhere: this is a short, dimmed preview, and
  /// [onToggleFold] moves it here.
  final bool isPreview;

  /// Its count opens its replies on their own page even though it can fold, as
  /// they aren't listed below it.
  final bool countOpensReplies;

  /// How many unseen posts folding hides below it.
  final int newReplies;

  /// See [ThreadPostComment.onTapQuote].
  final bool Function(int post)? onTapQuote;

  /// See [ThreadPostComment.repliedTo].
  final int? repliedTo;

  /// Where the post is in the thread, as the order listed may differ.
  final int? number;

  @override
  State<ThreadPagePost> createState() => _ThreadPagePostState();
}

class _ThreadPagePostState extends State<ThreadPagePost> {
  final GlobalKey _mediaBoxKey = GlobalKey();

  /// Where the viewer zooms the media from: its box in the post, below the
  /// thread's title bar (the body's top padding).
  MediaZoomOrigin? _zoomOrigin() {
    final int? width = widget.post.w;
    final int? height = widget.post.h;
    if (width == null || height == null || height <= 0) {
      return null;
    }
    return MediaZoomOrigin(
      boxKey: _mediaBoxKey,
      postId: widget.post.no,
      clipTop: MediaQuery.paddingOf(context).top,
      aspectRatio: width / height,
      imageSize: widget.post.isVideo
          ? null
          : Size(width.toDouble(), height.toDouble()),
    );
  }

  Future<void> _openReplies() async {
    final focusedPostId = await Navigator.of(context).push<int>(
      BackSwipePageRoute(
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

  double _mediaAspectRatio() {
    final int width = widget.post.w ?? widget.post.tnW ?? 1;
    final int height = widget.post.h ?? widget.post.tnH ?? 1;
    final ratio = width / max(height, 1);
    return ratio.clamp(0.65, 1.8);
  }

  Widget _buildVideo() {
    if (!widget.post.hasFile) {
      return const SizedBox.shrink();
    }
    final mediaId = widget.post.tim;
    if (mediaId == null) {
      return _buildImage();
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
        boxKey: _mediaBoxKey,
        onTap: () => _openMediaViewer(
          widget.replies ?? widget.allPosts,
          widget.post,
          origin: _zoomOrigin(),
        ),
      );
    } catch (_) {
      return _buildImage();
    }
  }

  /// The post's image or video, under a cover while it's a spoiler.
  Widget _buildMedia() {
    final Widget media = widget.post.isVideo ? _buildVideo() : _buildImage();
    final int? upload = widget.post.spoilerUpload;
    if (upload == null) {
      return media;
    }
    return AspectRatio(
      aspectRatio: _mediaAspectRatio(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(mediaInlineRadius),
        child: SpoilerCover(upload: upload, child: media),
      ),
    );
  }

  /// A color to tell a poster's [id] apart by.
  Color _idColor(String id, bool isDark) => HSLColor.fromAHSL(
    1,
    id.codeUnits
        .fold<int>(0, (int hue, int unit) => (hue * 31 + unit) % 360)
        .toDouble(),
    0.6,
    isDark ? 0.7 : 0.35,
  ).toColor();

  /// The row's width in physical pixels, capped at the original's.
  int? _imageDecodeWidth(BuildContext context) {
    final double target =
        MediaQuery.sizeOf(context).width *
        MediaQuery.devicePixelRatioOf(context);
    final int? original = widget.post.w;
    return original == null ? target.round() : min(original, target.round());
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.22),
      child: const Center(child: CupertinoActivityIndicator(radius: 12)),
    );
  }

  /// A post shown in full elsewhere: as much as fits a few lines, beside a small
  /// thumbnail, which the whole row reacts to as one.
  Widget _buildPreview() {
    final String? com = widget.post.com;
    return Opacity(
      opacity: 0.6,
      child: IgnorePointer(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 60),
          child: ClipRect(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.post.hasFile)
                    Padding(
                      padding: EdgeInsets.only(right: com == null ? 0 : 10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox.square(
                          dimension: 60,
                          child: SpoilerCover(
                            upload: widget.post.spoilerUpload,
                            canReveal: false,
                            child: Image(
                              image: thumbnailImage(_thumbnailUrl()),
                              fit: BoxFit.cover,
                              errorBuilder: imageErrorPlaceholder,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (com != null)
                    Expanded(
                      child: ThreadPostComment(
                        com: com,
                        board: widget.board,
                        thread: widget.thread,
                        allPosts: widget.allPosts,
                        repliedTo: widget.repliedTo,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The image as a preview: its thumbnail, with the full image fading in
  /// over it. Opens the viewer when tapped.
  Widget _buildImage() {
    return GestureDetector(
      onTap: () => _openMediaViewer(
        widget.replies ?? widget.allPosts,
        widget.post,
        origin: _zoomOrigin(),
      ),
      child: AspectRatio(
        key: _mediaBoxKey,
        aspectRatio: _mediaAspectRatio(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(mediaInlineRadius),
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
              borderRadius: BorderRadius.circular(mediaInlineRadius),
              child: Image(
                // Decode at display size: a 4000px original fills ~48 MB once
                // decoded, for a row about 400pt wide.
                image: ResizeImage.resizeIfNeeded(
                  _imageDecodeWidth(context),
                  null,
                  fullImage(
                    urls.file(widget.board, widget.post.tim, widget.post.ext),
                  ),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Provider.of<ThemeChanger>(context).isDark;
    final Post post = widget.post;
    final Color muted = DashColors.muted(isDark);
    final int? time = post.time;
    final String? country = post.country;
    // What's interactive inside, like media or links, takes its own taps.
    final VoidCallback? fold = widget.onToggleFold;
    final bool folded = fold != null && widget.folded;
    final bool isPreview = fold != null && widget.isPreview;
    final bool opensReplies = fold == null || widget.countOpensReplies;
    final bool isHidden = folded || isPreview;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: fold,
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 11, 14, folded ? 11 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: -0.05,
                        color: muted,
                      ),
                      children: [
                        TextSpan(
                          text: unescape(cleanTags(post.name ?? 'Anonymous')),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1,
                            color: DashColors.text(isDark),
                          ),
                        ),
                        if (post.trip != null) TextSpan(text: ' ${post.trip}'),
                        if (post.capcode != null)
                          TextSpan(
                            text: ' ## ${post.capcode}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: DashColors.nsfw,
                            ),
                          ),
                        if (post.id != null)
                          TextSpan(
                            text: '   ID:${post.id}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _idColor(post.id!, isDark),
                            ),
                          ),
                        if (time != null)
                          TextSpan(
                            text:
                                '   ${timeAgo(DateTime.fromMillisecondsSinceEpoch(time * 1000))}',
                          ),
                        if (widget.number != null)
                          TextSpan(text: '   #${widget.number}'),
                        if (post.no != null) TextSpan(text: '   ${post.no}'),
                      ],
                    ),
                    // Room for these too, without cutting off the post's number.
                    maxLines:
                        post.id != null ||
                            post.trip != null ||
                            post.capcode != null
                        ? 2
                        : 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (country != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: SizedBox(
                      width: 16,
                      height: 11,
                      child: CountryFlag.fromCountryCode(country),
                    ),
                  ),
                if (widget.newReplies > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text(
                      '${widget.newReplies} new',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DashColors.accent,
                      ),
                    ),
                  ),
                if (widget.replyCount > 0 || isHidden)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: opensReplies && widget.replyCount > 0
                        ? _openReplies
                        : fold,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: 14,
                        top: 2,
                        bottom: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.replyCount > 0) ...[
                            Text(
                              '${widget.replyCount}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: muted,
                              ),
                            ),
                            const SizedBox(width: 3),
                          ],
                          Icon(
                            opensReplies && widget.replyCount > 0
                                ? CupertinoIcons.reply
                                : isHidden
                                ? CupertinoIcons.chevron_right
                                : CupertinoIcons.chevron_down,
                            size: 12,
                            color: muted,
                          ),
                          // Its count opens its replies: this still says it's
                          // folded.
                          if (folded &&
                              widget.countOpensReplies &&
                              widget.replyCount > 0) ...[
                            const SizedBox(width: 6),
                            Icon(
                              CupertinoIcons.chevron_right,
                              size: 12,
                              color: muted,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            if (isPreview) ...[const SizedBox(height: 5), _buildPreview()],
            if (!folded && !isPreview && post.sub != null) ...[
              const SizedBox(height: 6),
              Text(
                unescape(cleanTags(post.sub ?? '')),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: DashColors.text(isDark),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (!folded && !isPreview && post.com != null) ...[
              const SizedBox(height: 5),
              ThreadPostComment(
                com: post.com ?? '',
                board: widget.board,
                thread: widget.thread,
                allPosts: widget.allPosts,
                onTap: fold,
                onTapQuote: widget.onTapQuote,
                repliedTo: widget.repliedTo,
              ),
            ],
            if (!folded && !isPreview && post.hasFile) ...[
              const SizedBox(height: 8),
              _buildMedia(),
            ],
          ],
        ),
      ),
    );
  }
}
