import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/save_videos.dart';
import 'package:flutter_chan/API/urls.dart' as urls;
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/saved_attachments_model.dart';
import 'package:flutter_chan/pages/media/shared_media_viewer.dart';
import 'package:flutter_chan/services/image_cache.dart';
import 'package:flutter_chan/services/reverse_image_search.dart';
import 'package:flutter_chan/widgets/media_video.dart';
import 'package:provider/provider.dart';

/// The media in a post the viewer was opened from: it zooms out of this box
/// and, if the same post is still shown when it closes, back into it.
class MediaZoomOrigin {
  const MediaZoomOrigin({
    required this.boxKey,
    required this.postId,
    required this.clipTop,
    required this.aspectRatio,
    this.imageSize,
  });

  /// On the media's box in the post; measured every frame, as it may move.
  final GlobalKey boxKey;
  final int? postId;

  /// Bottom of the thread's title bar: the zoom starts below it, so the
  /// bar stays on top.
  final double clipTop;

  /// The media's own shape, as it's laid out fullscreen.
  final double aspectRatio;

  /// For an image: its size, as the viewer doesn't enlarge small ones.
  final Size? imageSize;

  Rect? get rect {
    final RenderObject? box = boxKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      return null;
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }
}

class ThreadMediaViewerRoute extends MaterialPageRoute<int>
    implements MediaZoomTransition {
  ThreadMediaViewerRoute({
    required List<Post> mediaPosts,
    required int initialIndex,
    required String board,
    required int thread,
    MediaZoomOrigin? origin,
  }) : this._(
         mediaPosts: mediaPosts,
         initialIndex: initialIndex,
         board: board,
         thread: thread,
         origin: origin,
         currentPostId: ValueNotifier<int?>(
           _resolveInitialPostId(mediaPosts, initialIndex),
         ),
       );

  ThreadMediaViewerRoute._({
    required List<Post> mediaPosts,
    required int initialIndex,
    required String board,
    required int thread,
    required this.origin,
    required ValueNotifier<int?> currentPostId,
  }) : _currentPostId = currentPostId,
       super(
         // Keeps the thread from sliding aside (iOS parallax) while the
         // video zooms out of it, which pulled the zoom left and back.
         fullscreenDialog: true,
         builder: (BuildContext context) => ThreadMediaViewerPage(
           mediaPosts: mediaPosts,
           initialIndex: initialIndex,
           board: board,
           thread: thread,
           currentPostIdNotifier: currentPostId,
         ),
       );

  final ValueNotifier<int?> _currentPostId;
  final MediaZoomOrigin? origin;

  @override
  int? get currentResult => _currentPostId.value;

  // Like a photo viewer: opened from a post, the media zooms out of its box
  // there, and back into it when closed, while the viewer's background fades
  // in place. It's part of this route (not a Hero, which flies above every
  // route), so the viewer's bars stay above the media and, clipped below it,
  // the thread's title bar too. Otherwise it fades.
  @override
  Duration get transitionDuration => const Duration(milliseconds: 250);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);

  // ---------------------------
  // Back swipe
  // ---------------------------

  // The edge swipe drives the route's animation the way Flutter's
  // Cupertino back gesture does, so the thread shows underneath. Opened
  // from a post, only the media follows the finger (the background fades)
  // and, let go, it flies back into its post, like Photos. Otherwise the
  // whole viewer slides, like iOS's back swipe.

  /// The navigator told of the swipe; told again when it's settled. Kept,
  /// as the route forgets its navigator once it's gone.
  NavigatorState? _gesture;

  /// Whether this swipe moves just the media (decided when it starts).
  bool _swipeZooms = false;

  /// The animation's value when the swipe let go to close, zooming the
  /// media back from where the finger left it.
  double? _flyFrom;

  bool get _swiping => _gesture != null;

  void _swipeStart() {
    if (_gesture != null) {
      return;
    }
    final NavigatorState? navigator = this.navigator;
    if (navigator == null) {
      return;
    }
    _gesture = navigator..didStartUserGesture();
    _swipeZooms = _zoomable;
    _flyFrom = null;
  }

  /// [delta] is the finger's movement as a fraction of the screen width.
  void _swipeUpdate(double delta) {
    if (_gesture == null) {
      return;
    }
    controller!.value -= delta;
  }

  /// [velocity] is in screen widths per second.
  void _swipeEnd(double velocity) {
    final NavigatorState? navigator = _gesture;
    if (navigator == null) {
      return;
    }
    final AnimationController controller = this.controller!;
    final bool stay = velocity.abs() >= 1
        ? velocity <= 0
        : controller.value > 0.5;

    if (stay) {
      controller.animateTo(
        1,
        duration: _swipeSettleDuration(1 - controller.value),
        curve: Curves.fastLinearToSlowEaseIn,
      );
    } else {
      if (_swipeZooms) {
        _flyFrom = max(controller.value, 0.01);
      }
      navigator.pop(currentResult);
      if (controller.isAnimating) {
        controller.animateBack(
          0,
          duration: _flyFrom != null
              ? reverseTransitionDuration
              : _swipeSettleDuration(controller.value),
          curve: _flyFrom != null
              ? Curves.easeOutCubic
              : Curves.fastLinearToSlowEaseIn,
        );
      }
    }

    if (controller.isAnimating) {
      late final AnimationStatusListener listener;
      listener = (AnimationStatus status) {
        if (!status.isAnimating) {
          controller.removeStatusListener(listener);
          _swipeDone(navigator);
        }
      };
      controller.addStatusListener(listener);
    } else {
      _swipeDone(navigator);
    }
  }

  // The transition builders read the swipe state every frame; nothing to
  // rebuild.
  void _swipeDone(NavigatorState navigator) {
    if (_gesture != navigator) {
      return;
    }
    navigator.didStopUserGesture();
    _gesture = null;
    _flyFrom = null;
  }

  static Duration _swipeSettleDuration(double distance) =>
      Duration(milliseconds: (300 * distance).round().clamp(80, 300));

  /// Opened from a post whose media is still the one shown and on screen.
  bool get _zoomable {
    final MediaZoomOrigin? origin = this.origin;
    return origin != null &&
        _currentPostId.value == origin.postId &&
        origin.rect != null;
  }

  /// Zooming or moving just the media (not fading or sliding the viewer).
  bool get _zooms => _swiping ? _swipeZooms : _zoomable;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // The same widgets in every mode; only their values change, so the
    // viewer keeps its state when the mode does (e.g. a swipe starting).
    return AnimatedBuilder(
      animation: animation,
      child: _EdgeSwipeToClose(route: this, child: child),
      builder: (context, page) {
        final double value = animation.value;
        double opacity = 1;
        double slide = 0;
        if (!_zooms) {
          if (_swiping) {
            slide = (1 - value) * MediaQuery.sizeOf(context).width;
          } else {
            opacity = Curves.easeOut.transform(value);
          }
        }
        return Transform.translate(
          offset: Offset(slide, 0),
          child: Opacity(opacity: opacity, child: page),
        );
      },
    );
  }

  @override
  Widget buildBackgroundFade(BuildContext context, Widget background) {
    final Animation<double> animation = this.animation!;
    return AnimatedBuilder(
      animation: animation,
      child: background,
      builder: (context, background) {
        double opacity = 1;
        if (_zooms) {
          // Follows the finger directly while swiping.
          opacity = _swiping
              ? animation.value
              : Curves.easeOut.transform(animation.value);
        }
        return Opacity(opacity: opacity.clamp(0.0, 1.0), child: background);
      },
    );
  }

  @override
  Widget buildMediaZoom(BuildContext context, Widget media) {
    final Animation<double> animation = this.animation!;
    return AnimatedBuilder(
      animation: animation,
      child: media,
      builder: (context, media) {
        final Size screen = MediaQuery.sizeOf(context);
        final double value = animation.value;
        final MediaZoomOrigin? origin = this.origin;
        final Rect? from = origin?.rect;
        final Rect full = Offset.zero & screen;

        Widget place(Matrix4 transform, RRect? clip) => ClipRRect(
          clipBehavior: clip == null ? Clip.none : Clip.antiAlias,
          clipper: _RectClipper(clip ?? RRect.fromRectXY(full, 0, 0)),
          child: Transform(transform: transform, child: media),
        );

        if (!_zooms) {
          return place(Matrix4.identity(), null);
        }

        // Swiping: the media follows the finger, then flies home from there.
        double t = Curves.easeOutCubic.transform(value);
        double shift = 0;
        if (_swiping) {
          final double? flyFrom = _flyFrom;
          if (flyFrom == null || origin == null || from == null) {
            final double dx = (1 - value) * screen.width;
            return place(Matrix4.translationValues(dx, 0, 0), null);
          }
          t = (value / flyFrom).clamp(0.0, 1.0);
          shift = (1 - flyFrom) * screen.width * t;
        }

        if (origin == null || from == null || t >= 1) {
          return place(Matrix4.identity(), null);
        }

        final Rect video = _fullscreenRect(origin, screen);
        // Scaled so the media covers its box in the post, which crops it.
        final double startScale = max(
          from.width / video.width,
          from.height / video.height,
        );
        final double scale = startScale + (1 - startScale) * t;
        final Offset center =
            Offset.lerp(from.center, video.center, t)! + Offset(shift, 0);
        // Scales around the video's centre and moves that onto [center].
        final Matrix4 transform = Matrix4.diagonal3Values(scale, scale, 1)
          ..setTranslationRaw(
            center.dx - scale * video.center.dx,
            center.dy - scale * video.center.dy,
            0,
          );

        final Rect start = Rect.fromLTRB(
          from.left,
          max(from.top, origin.clipTop),
          from.right,
          max(from.bottom, origin.clipTop),
        );
        final Rect clip = Rect.lerp(start, full.shift(Offset(shift, 0)), t)!;
        final double radius = mediaInlineRadius * (1 - t);

        return place(
          transform,
          RRect.fromRectAndRadius(clip, Radius.circular(radius)),
        );
      },
    );
  }

  /// Where the media sits fullscreen: centred, as large as fits, or an image
  /// at most its own size ([SharedMediaViewer] lays them out like that).
  static Rect _fullscreenRect(MediaZoomOrigin origin, Size screen) {
    final Size? imageSize = origin.imageSize;
    if (imageSize != null) {
      final Size fitted = fittedImageSize(imageSize, screen);
      return Rect.fromCenter(
        center: screen.center(Offset.zero),
        width: fitted.width,
        height: fitted.height,
      );
    }
    final double aspectRatio = origin.aspectRatio;
    double width = screen.width;
    double height = width / aspectRatio;
    if (height > screen.height) {
      height = screen.height;
      width = height * aspectRatio;
    }
    return Rect.fromCenter(
      center: screen.center(Offset.zero),
      width: width,
      height: height,
    );
  }

  @override
  void dispose() {
    final NavigatorState? gesture = _gesture;
    if (gesture != null) {
      _swipeDone(gesture);
    }
    _currentPostId.dispose();
    super.dispose();
  }

  static int? _resolveInitialPostId(List<Post> mediaPosts, int initialIndex) {
    if (mediaPosts.isEmpty) {
      return null;
    }

    final int safeIndex = initialIndex.clamp(0, mediaPosts.length - 1);
    final Post initialPost = mediaPosts[safeIndex];
    return initialPost.no ?? initialPost.tim;
  }
}

class ThreadMediaViewerPage extends StatefulWidget {
  const ThreadMediaViewerPage({
    super.key,
    required this.mediaPosts,
    required this.initialIndex,
    required this.board,
    required this.thread,
    required this.currentPostIdNotifier,
  });

  final List<Post> mediaPosts;
  final int initialIndex;
  final String board;
  final int thread;
  final ValueNotifier<int?> currentPostIdNotifier;

  @override
  State<ThreadMediaViewerPage> createState() => _ThreadMediaViewerPageState();
}

class _ThreadMediaViewerPageState extends State<ThreadMediaViewerPage> {
  late int _currentIndex;

  // Each post saves, downloads, shares and is removed on its own (by _key),
  // so several can at once; saving shows from SavedAttachmentsProvider.
  final Set<String> _removing = <String>{};
  final Set<String> _downloading = <String>{};
  final Set<String> _sharing = <String>{};
  // How far along each is (see SaveProgress).
  final Map<String, ValueNotifier<double?>> _downloadProgress =
      <String, ValueNotifier<double?>>{};
  final Map<String, ValueNotifier<double?>> _shareProgress =
      <String, ValueNotifier<double?>>{};
  // A post's check mark after a save or download shows while its timer runs.
  final Map<String, Timer> _savedChecks = <String, Timer>{};
  final Map<String, Timer> _downloadedChecks = <String, Timer>{};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    widget.currentPostIdNotifier.value = _currentPostId;
  }

  @override
  void dispose() {
    for (final Timer timer in [
      ..._savedChecks.values,
      ..._downloadedChecks.values,
    ]) {
      timer.cancel();
    }
    super.dispose();
  }

  Post get _currentPost => widget.mediaPosts[_currentIndex];

  int? get _currentPostId => _currentPost.no ?? _currentPost.tim;

  String _mediaUrl(Post post) => urls.file(widget.board, post.tim, post.ext);

  String _fileName(Post post) => '${post.filename}${post.ext}';
  // `tim` is unique per upload; user-provided `filename` is not.
  String _downloadName(Post post) => '${post.tim}${post.ext}';

  /// Which upload [post] is: its `tim`, as saved attachments know it.
  String _key(Post post) => post.tim.toString();

  bool _isPostSaved(SavedAttachmentsProvider provider, Post post) {
    final String baseName = _key(post);
    return provider.getSavedAttachments().any(
      (a) => provider.attachmentId(a) == baseName,
    );
  }

  List<SharedMediaViewerItem> get _items {
    return widget.mediaPosts
        .map((Post post) {
          final String mediaUrl = _mediaUrl(post);

          return SharedMediaViewerItem(
            id: '${post.no ?? post.tim}',
            source: mediaUrl,
            isVideo: post.isVideo,
            imageProvider: fullImage(mediaUrl),
            thumbnail: thumbnailImage(urls.thumbnail(widget.board, post.tim)),
            width: post.w,
            height: post.h,
            spoilerUpload: post.spoilerUpload,
          );
        })
        .toList(growable: false);
  }

  Future<void> _saveToAttachments() async {
    final savedAttachments = context.read<SavedAttachmentsProvider>();
    // The one being saved, even if the viewer moves on meanwhile.
    final Post post = _currentPost;
    final String key = _key(post);
    if (savedAttachments.isSaving(key)) {
      return;
    }
    if (_isPostSaved(savedAttachments, post)) {
      _showCheck(_savedChecks, key);
      return;
    }
    await savedAttachments.addSavedAttachments(
      context,
      widget.board,
      _fileName(post),
      _downloadName(post),
    );
    if (mounted && _isPostSaved(savedAttachments, post)) {
      _showCheck(_savedChecks, key);
    }
  }

  Future<void> _removeFromAttachments() async {
    final Post post = _currentPost;
    final String key = _key(post);
    if (!_removing.add(key)) {
      return;
    }
    setState(() {});
    await context.read<SavedAttachmentsProvider>().removeSavedAttachments(
      _downloadName(post),
      context,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _removing.remove(key);
    });
  }

  /// Shows [key]'s check mark in [checks] for a moment.
  void _showCheck(Map<String, Timer> checks, String key) {
    checks[key]?.cancel();
    setState(() {
      checks[key] = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) {
          setState(() {
            checks.remove(key);
          });
        }
      });
    });
  }

  Future<void> _downloadToGallery() async {
    final Post post = _currentPost;
    final String key = _key(post);
    if (!_downloading.add(key)) {
      return;
    }
    final ValueNotifier<double?> progress = ValueNotifier<double?>(null);
    setState(() {
      _downloadProgress[key] = progress;
    });
    final bool saved = await saveVideo(
      _mediaUrl(post),
      _fileName(post),
      context,
      onProgress: (double? value) => progress.value = value,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _downloading.remove(key);
      _downloadProgress.remove(key);
    });
    if (saved) {
      _showCheck(_downloadedChecks, key);
    }
  }

  /// Gets the post ready to share, and opens the share sheet for it once
  /// it's free (shareInTurn), even if the viewer has moved on by then.
  Future<void> _shareCurrentMedia() async {
    final Post post = _currentPost;
    final String key = _key(post);
    if (!_sharing.add(key)) {
      return;
    }
    final ValueNotifier<double?> progress = ValueNotifier<double?>(null);
    setState(() {
      _shareProgress[key] = progress;
    });
    await shareMedia(
      _mediaUrl(post),
      _fileName(post),
      context,
      onProgress: (double? value) => progress.value = value,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _sharing.remove(key);
      _shareProgress.remove(key);
    });
  }

  void _closeWithCurrentPost() {
    Navigator.of(context).pop(_currentPostId);
  }

  @override
  Widget build(BuildContext context) {
    final savedAttachments = context.watch<SavedAttachmentsProvider>();
    final isSaved = _isPostSaved(savedAttachments, _currentPost);
    final String key = _key(_currentPost);

    return SharedMediaViewer(
      items: _items,
      initialIndex: _currentIndex,
      onClose: _closeWithCurrentPost,
      mediaNameBuilder: (int index) => _fileName(widget.mediaPosts[index]),
      onIndexChanged: (int index) {
        if (index == _currentIndex) {
          return;
        }
        setState(() {
          _currentIndex = index;
        });
        widget.currentPostIdNotifier.value = _currentPostId;
      },
      actions: [
        if (isSaved)
          SharedMediaViewerAction(
            icon: CupertinoIcons.trash,
            onPressed: (_) => _removeFromAttachments(),
            isBusy: _removing.contains(key),
          )
        else
          SharedMediaViewerAction(
            icon: CupertinoIcons.add_circled,
            onPressed: (_) => _saveToAttachments(),
            isBusy: savedAttachments.isSaving(key),
            progress: savedAttachments.saveProgressOf(key),
            isCompleted: _savedChecks.containsKey(key),
          ),
        SharedMediaViewerAction(
          icon: CupertinoIcons.arrow_down_to_line,
          onPressed: (_) => _downloadToGallery(),
          isBusy: _downloading.contains(key),
          progress: _downloadProgress[key],
          isCompleted: _downloadedChecks.containsKey(key),
        ),
        SharedMediaViewerAction(
          icon: CupertinoIcons.share,
          onPressed: (_) => _shareCurrentMedia(),
          isBusy: _sharing.contains(key),
          progress: _shareProgress[key],
        ),
        SharedMediaViewerAction(
          icon: CupertinoIcons.search,
          // Search engines only take images, so videos use their thumbnail.
          onPressed: (BuildContext anchor) => showReverseImageSearchMenu(
            anchor,
            _currentPost.isVideo
                ? urls.thumbnail(widget.board, _currentPost.tim)
                : _mediaUrl(_currentPost),
          ),
        ),
      ],
    );
  }
}

/// The back swipe from the left edge: the viewer follows the finger and
/// closes or snaps back on release, like iOS's own.
class _EdgeSwipeToClose extends StatelessWidget {
  const _EdgeSwipeToClose({required this.route, required this.child});

  // Video scrubbing leaves drags this close to the edge alone.
  static const double _edgeWidth = 20;

  final ThreadMediaViewerRoute route;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    double width() => MediaQuery.sizeOf(context).width;

    return Stack(
      children: [
        child,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: _edgeWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => route._swipeStart(),
            onHorizontalDragUpdate: (details) =>
                route._swipeUpdate(details.primaryDelta! / width()),
            onHorizontalDragEnd: (details) =>
                route._swipeEnd((details.primaryVelocity ?? 0) / width()),
            // Only a drag that started has a swipe to settle.
            onHorizontalDragCancel: () => route._swipeEnd(0),
          ),
        ),
      ],
    );
  }
}

class _RectClipper extends CustomClipper<RRect> {
  const _RectClipper(this.rect);

  final RRect rect;

  @override
  RRect getClip(Size size) => rect;

  @override
  bool shouldReclip(_RectClipper oldClipper) => oldClipper.rect != rect;
}
