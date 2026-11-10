import 'dart:math';

import 'package:country_flags/country_flags.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/chan/post_text.dart';
import 'package:flutter_chan/media/image_cache.dart';
import 'package:flutter_chan/media/inline_video.dart';
import 'package:flutter_chan/media/post_thumbnail.dart';
import 'package:flutter_chan/media/spoiler_cover.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/thread/media_viewer_route.dart';
import 'package:flutter_chan/thread/post_menu.dart';
import 'package:flutter_chan/thread/posts_by_id_page.dart';
import 'package:flutter_chan/thread/thread_post_comment.dart';
import 'package:flutter_chan/thread/thread_posts.dart';
import 'package:flutter_chan/thread/thread_replies.dart';
import 'package:flutter_chan/ui/back_swipe_route.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:provider/provider.dart';

/// A post as a row: a one-line header, then its text, then its image or
/// video. Tapping it folds it down to its header, along with any replies
/// listed below it; holding it offers to hide it, or posts like it.
class ThreadPagePost extends StatefulWidget {
  const ThreadPagePost({
    super.key,
    required this.post,
    required this.thread,
    this.onViewerMovedTo,
    this.mediaOrder,
    this.replyCount = 0,
    this.preloadVideo = false,
    this.onToggleFold,
    this.folded = false,
    this.isPreview = false,
    this.countOpensReplies = false,
    this.newReplies = 0,
    this.onTapQuote,
    this.repliedTo,
    this.hiddenBecause,
    this.onReveal,
    this.isLifted = false,
  });

  final ThreadPosts thread;
  final Post post;

  /// The media viewer was left on another post.
  final ValueChanged<int>? onViewerMovedTo;

  /// The order to swipe through media in, if not the thread's.
  final List<Post>? mediaOrder;
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

  /// Why it's hidden, if it is: it's just this line then, until tapped to
  /// [onReveal] it.
  final String? hiddenBecause;
  final VoidCallback? onReveal;

  /// It's a copy lifted off the list while its menu is open: a video is a
  /// still, as the post in the list already plays it.
  final bool isLifted;

  @override
  State<ThreadPagePost> createState() => _ThreadPagePostState();
}

class _ThreadPagePostState extends State<ThreadPagePost> {
  final GlobalKey _mediaBoxKey = GlobalKey();

  /// Lifted off the list with its menu: the copy over the page shows instead.
  bool _isLifted = false;

  late final TapGestureRecognizer _idTap = TapGestureRecognizer()
    ..onTap = _openPostsById;

  @override
  void dispose() {
    _idTap.dispose();
    super.dispose();
  }

  Future<void> _showMenu() async {
    setState(() => _isLifted = true);
    await showPostMenu(
      context,
      post: widget.post,
      thread: widget.thread,
      preview: (_) => ThreadPagePost(
        post: widget.post,
        thread: widget.thread,
        replyCount: widget.replyCount,
        // Only to look the same: the copy takes no taps.
        onToggleFold: widget.onToggleFold == null ? null : () {},
        folded: widget.folded,
        isPreview: widget.isPreview,
        countOpensReplies: widget.countOpensReplies,
        newReplies: widget.newReplies,
        repliedTo: widget.repliedTo,
        hiddenBecause: widget.hiddenBecause,
        isLifted: true,
      ),
    );
    if (mounted) {
      setState(() => _isLifted = false);
    }
  }

  void _openPostsById() {
    final String? id = widget.post.id;
    if (id == null) {
      return;
    }
    Navigator.of(context).push(
      BackSwipePageRoute<void>(
        builder: (context) => PostsByIdPage(id: id, thread: widget.thread),
      ),
    );
  }

  /// The line in place of a hidden post, saying why; tapping shows the post.
  Widget _buildHidden(String reason, bool isDark) {
    final Color muted = DashColors.muted(isDark);
    final TextStyle small = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: muted,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onReveal,
      onLongPress: _showMenu,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            Icon(CupertinoIcons.eye_slash, size: 13, color: muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                reason,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: small,
              ),
            ),
            if (widget.newReplies > 0)
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(
                  '${widget.newReplies} new',
                  style: small.copyWith(
                    fontWeight: FontWeight.w600,
                    color: context.accent,
                  ),
                ),
              ),
            if (widget.replyCount > 0) ...[
              const SizedBox(width: 10),
              Text('${widget.replyCount}', style: small),
              const SizedBox(width: 3),
              Icon(CupertinoIcons.reply, size: 12, color: muted),
            ],
            const SizedBox(width: 12),
            Text(
              'Show',
              style: small.copyWith(
                fontWeight: FontWeight.w600,
                color: context.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

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

  void _openReplies() {
    Navigator.of(context).push(
      BackSwipePageRoute<void>(
        builder: (context) =>
            ThreadReplies(post: widget.post, thread: widget.thread),
      ),
    );
  }

  Future<void> _openMediaViewer() async {
    final List<Post> mediaPosts = (widget.mediaOrder ?? widget.thread.posts)
        .where((Post post) => post.hasFile)
        .toList();
    final int index = mediaPosts.indexWhere((p) => p.no == widget.post.no);
    if (index < 0) {
      return;
    }
    final int? focusedPost = await Navigator.of(context).push<int>(
      ThreadMediaViewerRoute(
        mediaPosts: mediaPosts,
        initialIndex: index,
        origin: _zoomOrigin(),
      ),
    );
    // Only scroll the thread to a post swiped to in the viewer: scrolling
    // now would also move the video zooming back into this post.
    if (mounted && focusedPost != null && focusedPost != widget.post.no) {
      widget.onViewerMovedTo?.call(focusedPost);
    }
  }

  double _mediaAspectRatio() {
    final int width = widget.post.w ?? widget.post.tnW ?? 1;
    final int height = widget.post.h ?? widget.post.tnH ?? 1;
    final ratio = width / max(height, 1);
    return ratio.clamp(0.65, 1.8);
  }

  Widget _buildVideo() {
    final SettingsProvider settings = Provider.of<SettingsProvider>(context);
    final Post post = widget.post;
    return InlineVideo(
      key: ValueKey('inline-video-${post.board}-${post.no}'),
      videoUrl: post.fileUrl,
      thumbnailUrl: post.thumbnailUrl,
      aspectRatio: _mediaAspectRatio(),
      videoWidth: post.w,
      videoHeight: post.h,
      preload: widget.preloadVideo,
      autoplay: !settings.dataSaver.value,
      startMuted: settings.feedVideosStartMuted.value,
      boxKey: _mediaBoxKey,
      onTap: _openMediaViewer,
    );
  }

  Widget _buildMedia() {
    final Widget media = !widget.post.isVideo
        ? _buildImage()
        : widget.isLifted
        ? _buildStill()
        : _buildVideo();
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

  /// A video's thumbnail, marked as one.
  Widget _buildStill() {
    return AspectRatio(
      aspectRatio: _mediaAspectRatio(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(mediaInlineRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image(
              image: thumbnailImage(widget.post.thumbnailUrl),
              fit: BoxFit.cover,
              errorBuilder: imageErrorPlaceholder,
            ),
            Center(
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.play_fill,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _idColor(String id, bool isDark) => HSLColor.fromAHSL(
    1,
    id.codeUnits
        .fold<int>(0, (int hue, int unit) => (hue * 31 + unit) % 360)
        .toDouble(),
    0.6,
    isDark ? 0.7 : 0.35,
  ).toColor();

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
                              image: thumbnailImage(widget.post.thumbnailUrl),
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
                        thread: widget.thread,
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

  Widget _buildImage() {
    final bool dataSaver = Provider.of<SettingsProvider>(
      context,
    ).dataSaver.value;
    return GestureDetector(
      onTap: _openMediaViewer,
      child: AspectRatio(
        key: _mediaBoxKey,
        aspectRatio: _mediaAspectRatio(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(mediaInlineRadius),
              child: Image(
                image: thumbnailImage(widget.post.thumbnailUrl),
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
            if (!dataSaver)
              ClipRRect(
                borderRadius: BorderRadius.circular(mediaInlineRadius),
                child: Image(
                  // Decode at display size: a 4000px original fills ~48 MB once
                  // decoded, for a row about 400pt wide.
                  image: ResizeImage.resizeIfNeeded(
                    _imageDecodeWidth(context),
                    null,
                    fullImage(widget.post.fileUrl),
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
                  frameBuilder:
                      (context, child, frame, wasSynchronouslyLoaded) {
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
    final bool isDark = context.isDark;
    final Post post = widget.post;
    final int? place = widget.thread.places[post.no];
    final Color muted = DashColors.muted(isDark);
    final int? time = post.time;
    final String? country = post.country;
    // What's interactive inside, like media or links, takes its own taps.
    final VoidCallback? fold = widget.onToggleFold;
    final bool folded = fold != null && widget.folded;
    final bool isPreview = fold != null && widget.isPreview;
    final bool opensReplies = fold == null || widget.countOpensReplies;
    final bool isHidden = folded || isPreview;
    final String? id = post.id;
    final int idPosts = id == null
        ? 0
        : widget.thread.postsById[id]?.length ?? 0;

    if (widget.hiddenBecause case final String reason) {
      return Opacity(
        opacity: _isLifted ? 0 : 1,
        child: _buildHidden(reason, isDark),
      );
    }

    final Widget row = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: fold,
      onLongPress: _showMenu,
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
                          text: plainText(post.name ?? 'Anonymous'),
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
                              color: DashColors.danger,
                            ),
                          ),
                        if (id != null) ...[
                          const TextSpan(text: '   '),
                          // Opens the poster's other posts, with how many
                          // there are.
                          TextSpan(
                            text: idPosts > 1 ? 'ID:$id ($idPosts)' : 'ID:$id',
                            recognizer: _idTap,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _idColor(id, isDark),
                            ),
                          ),
                        ],
                        if (time != null)
                          TextSpan(
                            text:
                                '   ${_timeAgo(DateTime.fromMillisecondsSinceEpoch(time * 1000))}',
                          ),
                        if (place != null) TextSpan(text: '   #$place'),
                        TextSpan(text: '   ${post.no}'),
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
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.accent,
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
                            semanticLabel: widget.replyCount > 0
                                ? 'replies'
                                : isHidden
                                ? 'Folded'
                                : 'Open',
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
                plainText(post.sub ?? ''),
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
                thread: widget.thread,
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
    // Still taking its room, so nothing moves under the copy.
    return Opacity(opacity: _isLifted ? 0 : 1, child: row);
  }
}

String _timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) {
    return 'just now';
  }
  if (diff.inHours < 1) {
    return '${diff.inMinutes}m ago';
  }
  if (diff.inDays < 1) {
    return '${diff.inHours}h ago';
  }
  return '${diff.inDays}d ago';
}
