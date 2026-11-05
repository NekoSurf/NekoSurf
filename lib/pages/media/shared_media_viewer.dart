import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:flutter_chan/widgets/dash_dialogs.dart';
import 'package:flutter_chan/widgets/frosted.dart';
import 'package:flutter_chan/widgets/media_video.dart';
import 'package:flutter_chan/widgets/spoiler_cover.dart';
import 'package:flutter_chan/widgets/video_scrub_gesture.dart';
import 'package:preload_page_view/preload_page_view.dart';
import 'package:provider/provider.dart';

/// A button in the viewer's top bar.
class SharedMediaViewerAction {
  const SharedMediaViewerAction({
    required this.icon,
    required this.onPressed,
    this.isBusy = false,
    this.progress,
    this.isCompleted = false,
  });

  final IconData icon;

  /// Gets the button's context, to anchor a menu to it.
  final ValueChanged<BuildContext> onPressed;

  /// Busy: it can't be pressed, and shows how far along it is instead.
  final bool isBusy;

  /// While busy, from 0 to 1 (see SaveProgress): a ring fills up while it's
  /// known, a spinner shows while it's null.
  final ValueListenable<double?>? progress;

  /// Just done: it can't be pressed, and shows a check mark for now.
  final bool isCompleted;
}

class SharedMediaViewerItem {
  const SharedMediaViewerItem({
    required this.id,
    required this.source,
    required this.isVideo,
    required this.imageProvider,
    this.resolveVideoSource,
    this.thumbnail,
    this.width,
    this.height,
    this.spoilerUpload,
  });

  final String id;
  final String source;
  final bool isVideo;
  final ImageProvider<Object> imageProvider;
  final MediaSourceResolver? resolveVideoSource;
  final ImageProvider<Object>? thumbnail;

  /// The video's size, when known up front.
  final int? width;
  final int? height;

  /// See [SpoilerCover.upload].
  final int? spoilerUpload;
}

/// A scrollable ignores touches while its page settles, which blocks zoom;
/// a stiffer spring keeps that window short.
class _SnappyPagePhysics extends ClampingScrollPhysics {
  const _SnappyPagePhysics({super.parent});

  @override
  _SnappyPagePhysics applyTo(ScrollPhysics? ancestor) =>
      _SnappyPagePhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring => SpringDescription.withDampingRatio(
    mass: 0.5,
    stiffness: 1400,
    ratio: 1.0,
  );
}

class SharedMediaViewer extends StatefulWidget {
  const SharedMediaViewer({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.onClose,
    required this.mediaNameBuilder,
    required this.actions,
    required this.onIndexChanged,
  });

  final List<SharedMediaViewerItem> items;
  final int initialIndex;
  final VoidCallback onClose;
  final List<SharedMediaViewerAction> actions;
  final ValueChanged<int> onIndexChanged;

  final String Function(int index) mediaNameBuilder;

  @override
  State<SharedMediaViewer> createState() => _SharedMediaViewerState();
}

class _SharedMediaViewerState extends State<SharedMediaViewer> {
  static const int _precacheRadius = 3;

  late final PreloadPageController _pageController;
  late int _currentIndex;
  bool _isVideoScrubbing = false;
  bool _isImageZoomed = false;
  bool _chromeVisible = true;

  static const List<double> _rates = [1.0, 1.25, 1.5, 2.0, 0.5];

  /// Playback speed for every video in this viewer session.
  double _rate = 1.0;

  void _toggleChrome() => setState(() => _chromeVisible = !_chromeVisible);

  void _cycleRate() {
    setState(() {
      _rate = _rates[(_rates.indexOf(_rate) + 1) % _rates.length];
    });
  }

  void _advanceAfter(int index) {
    // Only if that video is still the one showing, and there's a next item.
    if (!mounted ||
        index != _currentIndex ||
        index >= widget.items.length - 1 ||
        !_pageController.hasClients) {
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = _sanitizeIndex(widget.initialIndex, widget.items.length);
    _pageController = PreloadPageController(initialPage: _currentIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _precacheAround(_currentIndex);
      }
    });
  }

  /// Only one page per side is built; neighbouring video pages download
  /// their files. Images further out are still warmed up so paging stays
  /// smooth.
  void _precacheAround(int index) {
    for (int i = index - _precacheRadius; i <= index + _precacheRadius; i++) {
      if (i < 0 || i >= widget.items.length || (i - index).abs() <= 1) {
        continue;
      }

      final SharedMediaViewerItem item = widget.items[i];
      final ImageProvider<Object>? image = item.isVideo
          ? item.thumbnail
          : item.imageProvider;
      if (image != null) {
        unawaited(precacheImage(image, context, onError: (_, _) {}));
      }
    }
  }

  @override
  void didUpdateWidget(covariant SharedMediaViewer oldWidget) {
    super.didUpdateWidget(oldWidget);

    final int nextIndex = _sanitizeIndex(
      widget.initialIndex,
      widget.items.length,
    );
    final bool itemListChanged = oldWidget.items.length != widget.items.length;
    final bool indexChanged = nextIndex != _currentIndex;

    if (!itemListChanged && !indexChanged) {
      return;
    }

    _currentIndex = nextIndex;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) {
        return;
      }

      _pageController.jumpToPage(_currentIndex);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int _sanitizeIndex(int index, int itemCount) {
    if (itemCount <= 0) {
      return 0;
    }

    return index.clamp(0, itemCount - 1);
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final double topInset = MediaQuery.of(context).padding.top;
    final int itemCount = widget.items.length;
    final String mediaTitle = itemCount == 0
        ? ''
        : widget.mediaNameBuilder(_currentIndex);

    void showFileInfo() {
      showDashDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => DashDialog(
          title: const Text('File Information'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Filename: $mediaTitle'),
          ),
          actions: [
            DashDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      // Black comes from the background layer, which may fade in.
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: _zoomed(
              (zoom) => zoom.buildBackgroundFade,
              ColoredBox(color: Colors.black, child: _buildPagedBackdrop()),
            ),
          ),
          // Android's smaller platform touch slop lets page drags beat pinch-to-zoom.
          _zoomed(
            (zoom) => zoom.buildMediaZoom,
            MediaQuery(
              data: MediaQuery.of(context).copyWith(
                gestureSettings: const DeviceGestureSettings(
                  touchSlop: kTouchSlop,
                ),
              ),
              child: PreloadPageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                preloadPagesCount: 1,
                physics: _isVideoScrubbing || _isImageZoomed
                    ? const NeverScrollableScrollPhysics()
                    : const _SnappyPagePhysics(),
                itemCount: itemCount,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                    _isVideoScrubbing = false;
                    _isImageZoomed = false;
                  });
                  _precacheAround(index);
                  widget.onIndexChanged(index);
                },
                itemBuilder: (context, index) => SpoilerCover(
                  upload: widget.items[index].spoilerUpload,
                  // Its backdrop can show now too.
                  onRevealed: () => setState(() {}),
                  child: Builder(
                    builder: (context) {
                      final SharedMediaViewerItem item = widget.items[index];

                      if (item.isVideo) {
                        return _SharedMediaVideoPage(
                          key: ValueKey('shared-media-video-${item.id}'),
                          item: item,
                          isActive: _currentIndex == index,
                          chromeVisible: _chromeVisible,
                          onTap: _toggleChrome,
                          rate: _rate,
                          onCycleRate: _cycleRate,
                          autoAdvance: settings.getFullscreenAutoAdvance(),
                          onToggleAutoAdvance: () =>
                              settings.setFullscreenAutoAdvance(
                                !settings.getFullscreenAutoAdvance(),
                              ),
                          onCompleted: () => _advanceAfter(index),
                          onScrubStateChanged: (isScrubbing) {
                            if (!mounted || _isVideoScrubbing == isScrubbing) {
                              return;
                            }

                            setState(() {
                              _isVideoScrubbing = isScrubbing;
                            });
                          },
                        );
                      }

                      return _SharedMediaImagePage(
                        key: ValueKey('shared-media-image-${item.id}'),
                        item: item,
                        onTap: _toggleChrome,
                        onZoomStateChanged: (isZoomed) {
                          if (!mounted || _isImageZoomed == isZoomed) {
                            return;
                          }

                          setState(() {
                            _isImageZoomed = isZoomed;
                          });
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _Chrome(
              visible: _chromeVisible,
              hiddenOffset: -0.3,
              child: Container(
                padding: EdgeInsets.fromLTRB(12, topInset + 8, 12, 28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    _OverlayButton(
                      onPressed: widget.onClose,
                      child: const Icon(
                        CupertinoIcons.chevron_left,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: showFileInfo,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              mediaTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              itemCount == 0
                                  ? ''
                                  : '${_currentIndex + 1} of $itemCount',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (itemCount > 0)
                      Frosted(
                        radius: 16,
                        blur: 16,
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        color: _buttonBacking,
                        borderColor: _buttonBorder,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final SharedMediaViewerAction action
                                in widget.actions)
                              _buildActionButton(action),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Applies the route's zoom (see [MediaZoomTransition]) to one layer.
  Widget _zoomed(
    Widget Function(BuildContext, Widget) Function(MediaZoomTransition zoom)
    pick,
    Widget layer,
  ) {
    final Object? route = ModalRoute.of(context);
    if (route is! MediaZoomTransition) {
      return layer;
    }
    return pick(route)(context, layer);
  }

  Widget _buildPagedBackdrop() {
    if (widget.items.isEmpty) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _pageController,
      builder: (BuildContext context, Widget? child) {
        final int itemCount = widget.items.length;
        double page = _currentIndex.toDouble();

        if (_pageController.hasClients) {
          final double? pageValue = _pageController.page;
          if (pageValue != null) {
            page = pageValue;
          }
        }

        final int lower = page.floor().clamp(0, itemCount - 1);
        final int upper = page.ceil().clamp(0, itemCount - 1);
        final double t = (page - lower).abs().clamp(0.0, 1.0);

        final ImageProvider<Object>? lowerImage = _backdrop(
          widget.items[lower],
        );
        final ImageProvider<Object>? upperImage = _backdrop(
          widget.items[upper],
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            if (lowerImage != null)
              _buildBlurredBackdrop(lowerImage, upper == lower ? 1 : 1 - t),
            if (upper != lower && upperImage != null)
              _buildBlurredBackdrop(upperImage, t),
          ],
        );
      },
    );
  }

  ImageProvider<Object>? _backdrop(SharedMediaViewerItem item) =>
      isSpoilerCovered(item.spoilerUpload)
      ? null
      : item.thumbnail ?? item.imageProvider;

  Widget _buildBlurredBackdrop(ImageProvider<Object> image, double opacity) {
    return Opacity(
      opacity: opacity,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Image(
          image: image,
          fit: BoxFit.cover,
          color: Colors.black.withValues(alpha: 0.4),
          colorBlendMode: BlendMode.darken,
        ),
      ),
    );
  }

  Widget _buildActionButton(SharedMediaViewerAction action) {
    return Builder(
      builder: (buttonContext) => _OverlayButton(
        bare: true,
        onPressed: action.isBusy || action.isCompleted
            ? null
            : () => action.onPressed(buttonContext),
        // A busy button can't be pressed, but its spinner must stay visible.
        dimmed: action.isCompleted && !action.isBusy,
        child: action.isBusy
            ? _BusyIndicator(progress: action.progress)
            : Icon(
                action.isCompleted
                    ? CupertinoIcons.check_mark_circled_solid
                    : action.icon,
                color: Colors.white,
                size: 18,
              ),
      ),
    );
  }
}

/// Behind the top bar's buttons: dark, so their white icons and spinners
/// stand out on bright pictures as well as dark ones.
final Color _buttonBacking = Colors.black.withValues(alpha: 0.35);
final Color _buttonBorder = Colors.white.withValues(alpha: 0.12);

/// The viewer's controls: they slide away by [hiddenOffset] of their height
/// and fade when not [visible].
class _Chrome extends StatelessWidget {
  const _Chrome({
    required this.visible,
    required this.hiddenOffset,
    required this.child,
  });

  final bool visible;
  final double hiddenOffset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: Offset(0, visible ? 0 : hiddenOffset),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: RouteChromeFade(child: child),
        ),
      ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.onPressed,
    required this.child,
    this.bare = false,
    this.dimmed,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final bool bare;

  /// Drawn faded; by default when it can't be pressed.
  final bool? dimmed;

  @override
  Widget build(BuildContext context) {
    final Widget content = SizedBox.square(
      dimension: 40,
      child: Center(
        child: Opacity(
          opacity: (dimmed ?? onPressed == null) ? 0.5 : 1,
          child: child,
        ),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: bare
          ? content
          : Frosted(
              radius: 14,
              blur: 16,
              color: _buttonBacking,
              borderColor: _buttonBorder,
              child: content,
            ),
    );
  }
}

/// A busy button: a ring filling up as it gets along, a spinner while it
/// can't tell how far.
class _BusyIndicator extends StatelessWidget {
  const _BusyIndicator({this.progress});

  final ValueListenable<double?>? progress;

  static const Widget _spinner = CupertinoActivityIndicator(
    radius: 9,
    color: Colors.white,
  );

  @override
  Widget build(BuildContext context) {
    final ValueListenable<double?>? progress = this.progress;
    if (progress == null) {
      return _spinner;
    }
    return ValueListenableBuilder<double?>(
      valueListenable: progress,
      builder: (BuildContext context, double? value, _) =>
          value == null ? _spinner : _ProgressRing(value: value),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    // Eases between updates, which come in jumps of whole percent or more.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      builder: (BuildContext context, double value, _) => SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(
          value: value,
          strokeWidth: 2.2,
          strokeCap: StrokeCap.round,
          color: Colors.white,
          backgroundColor: Colors.white.withValues(alpha: 0.25),
          semanticsLabel: 'Progress',
          semanticsValue: '${(value * 100).round()}%',
        ),
      ),
    );
  }
}

class _SharedMediaVideoPage extends StatefulWidget {
  const _SharedMediaVideoPage({
    super.key,
    required this.item,
    required this.isActive,
    required this.chromeVisible,
    required this.onTap,
    required this.onScrubStateChanged,
    required this.rate,
    required this.onCycleRate,
    required this.autoAdvance,
    required this.onToggleAutoAdvance,
    required this.onCompleted,
  });

  final double rate;
  final VoidCallback onCycleRate;
  final bool autoAdvance;
  final VoidCallback onToggleAutoAdvance;

  /// The video reached its end; only fires with [autoAdvance] on.
  final VoidCallback onCompleted;
  final SharedMediaViewerItem item;
  final bool isActive;
  final bool chromeVisible;
  final VoidCallback onTap;
  final ValueChanged<bool> onScrubStateChanged;

  @override
  State<_SharedMediaVideoPage> createState() => _SharedMediaVideoPageState();
}

/// Shows the same [MediaVideo] as the inline post, so a video opened from a
/// thread just continues here (with sound). Only the page being shown wants
/// it playing; its neighbours just download theirs.
class _SharedMediaVideoPageState extends State<_SharedMediaVideoPage> {
  late final MediaVideo _video = MediaVideo.obtain(
    widget.item.source,
    resolveSource: widget.item.resolveVideoSource,
    width: widget.item.width,
    height: widget.item.height,
  );
  StreamSubscription<void>? _completedSub;

  @override
  void initState() {
    super.initState();
    _completedSub = _video.completed.listen((_) {
      if (mounted && widget.isActive && widget.autoAdvance) {
        widget.onCompleted();
      }
    });
    _video.prefetch();
    if (widget.isActive) {
      _activate();
    }
  }

  @override
  void didUpdateWidget(covariant _SharedMediaVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!oldWidget.isActive && widget.isActive) {
      _activate();
    } else if (oldWidget.isActive && !widget.isActive) {
      _deactivate();
    } else if (widget.isActive) {
      if (oldWidget.rate != widget.rate) {
        _video.setRate(widget.rate);
      }
      if (oldWidget.autoAdvance != widget.autoAdvance) {
        _video.setLoop(!widget.autoAdvance);
      }
    }
  }

  void _activate() {
    _video
      ..setRate(widget.rate)
      ..setLoop(!widget.autoAdvance)
      ..restartIfFinished()
      ..want(this, audible: true);
  }

  /// Back to how inline posts play it.
  void _deactivate() {
    _video
      ..unwant(this)
      ..setRate(1)
      ..setLoop(true);
  }

  @override
  void deactivate() {
    widget.onScrubStateChanged(false);
    super.deactivate();
  }

  @override
  void dispose() {
    unawaited(_completedSub?.cancel());
    if (widget.isActive) {
      _deactivate();
    }
    _video.release();
    super.dispose();
  }

  String _formatRate(double rate) {
    final String text = rate == rate.roundToDouble()
        ? rate.toStringAsFixed(0)
        : rate.toString();
    return '$text×';
  }

  @override
  Widget build(BuildContext context) {
    final ImageProvider<Object>? thumbnail = widget.item.thumbnail;
    final int? width = widget.item.width;
    final int? height = widget.item.height;
    final double? aspectRatio = width != null && height != null && height > 0
        ? width / height
        : null;
    final Widget view = MediaVideoView(
      video: _video,
      fit: BoxFit.contain,
      indicatorSize: 34,
      wakelock: true,
      thumbnail: thumbnail == null
          ? const SizedBox.shrink()
          : Image(image: thumbnail, fit: BoxFit.contain, gaplessPlayback: true),
    );
    // In its own box, centred: the viewer's zoom from an inline video
    // scales exactly this box into the post's.
    final Widget content = aspectRatio == null
        ? view
        : Center(
            child: AspectRatio(aspectRatio: aspectRatio, child: view),
          );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: VideoScrubGesture(
              video: _video,
              onScrubStateChanged: widget.onScrubStateChanged,
              child: SizedBox.expand(child: content),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _Chrome(
              visible: widget.chromeVisible,
              hiddenOffset: 0.3,
              child: ListenableBuilder(
                listenable: _video,
                builder: (context, _) => _buildControls(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final Duration duration = _video.duration;
    final double max =
        (duration.inMilliseconds <= 0 ? 1 : duration.inMilliseconds).toDouble();

    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        44,
        12,
        MediaQuery.paddingOf(context).bottom + 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.75), Colors.transparent],
        ),
      ),
      // No backdrop blur: over a playing video it had to be redone for
      // every frame.
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 18, 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E).withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: _video.togglePlay,
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: DashColors.accent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _video.isPlaying
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.play_fill,
                  color: Colors.black,
                  size: 17,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              // Only the slider and times follow the position.
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  _video.scrubPosition,
                  _video.position,
                  _video.loaded,
                ]),
                builder: (context, _) {
                  final Duration shown =
                      _video.scrubPosition.value ?? _video.position.value;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          activeTrackColor: DashColors.accent,
                          inactiveTrackColor: Colors.white.withValues(
                            alpha: 0.22,
                          ),
                          // What has loaded, like a stream's buffer.
                          secondaryActiveTrackColor: Colors.white.withValues(
                            alpha: 0.3,
                          ),
                          trackShape: _LoadedTrackShape(_video.loaded.value),
                          thumbColor: Colors.white,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
                        child: Slider(
                          value: shown.inMilliseconds.toDouble().clamp(0, max),
                          min: 0,
                          max: max,
                          // Live: the picture follows the thumb.
                          onChangeStart: duration > Duration.zero
                              ? (_) => _video.scrubStart()
                              : null,
                          onChanged: duration > Duration.zero
                              ? (value) => _video.scrubTo(
                                  Duration(milliseconds: value.round()),
                                )
                              : null,
                          onChangeEnd: (_) => _video.scrubEnd(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              formatVideoTime(shown),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              formatVideoTime(duration),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onCycleRate,
              child: Container(
                width: 46,
                padding: const EdgeInsets.symmetric(vertical: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: widget.rate == 1.0
                      ? Colors.white.withValues(alpha: 0.12)
                      : DashColors.accent.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _formatRate(widget.rate),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onToggleAutoAdvance,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
                child: Icon(
                  widget.autoAdvance
                      ? CupertinoIcons.forward_end_fill
                      : CupertinoIcons.repeat,
                  size: 20,
                  color: widget.autoAdvance ? DashColors.accent : Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The slider's track, with the parts of the video that have loaded drawn
/// ahead of the position: more than one after scrubbing ahead of the
/// download.
class _LoadedTrackShape extends RoundedRectSliderTrackShape {
  const _LoadedTrackShape(this.loaded);

  final List<(double, double)> loaded;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );
    final Rect track = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (thumbCenter.dx >= track.right) {
      return;
    }
    final Canvas canvas = context.canvas;
    final Paint paint = Paint()
      ..color = sliderTheme.secondaryActiveTrackColor ?? Colors.white24;
    canvas
      ..save()
      ..clipRRect(
        RRect.fromLTRBAndCorners(
          thumbCenter.dx,
          track.top,
          track.right,
          track.bottom,
          topRight: Radius.circular(track.height / 2),
          bottomRight: Radius.circular(track.height / 2),
        ),
      );
    for (final (double start, double end) in loaded) {
      canvas.drawRect(
        Rect.fromLTRB(
          track.left + start * track.width,
          track.top,
          track.left + end * track.width,
          track.bottom,
        ),
        paint,
      );
    }
    canvas.restore();
  }
}

class _SharedMediaImagePage extends StatefulWidget {
  const _SharedMediaImagePage({
    super.key,
    required this.item,
    required this.onTap,
    required this.onZoomStateChanged,
  });

  final SharedMediaViewerItem item;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoomStateChanged;

  @override
  State<_SharedMediaImagePage> createState() => _SharedMediaImagePageState();
}

/// The size an image of [imageSize] shows at on [screen]: as large as fits,
/// but no larger than its own size.
Size fittedImageSize(Size imageSize, Size screen) {
  final double scale = min(
    1,
    min(screen.width / imageSize.width, screen.height / imageSize.height),
  );
  return imageSize * scale;
}

class _SharedMediaImagePageState extends State<_SharedMediaImagePage>
    with SingleTickerProviderStateMixin {
  /// Where the thumbnail shows until the image is ready, if it has one.
  Size? _thumbnailSize(BuildContext context) {
    final SharedMediaViewerItem item = widget.item;
    final int? width = item.width;
    final int? height = item.height;
    if (item.thumbnail == null ||
        width == null ||
        height == null ||
        width <= 0 ||
        height <= 0) {
      return null;
    }
    return fittedImageSize(
      Size(width.toDouble(), height.toDouble()),
      MediaQuery.sizeOf(context),
    );
  }

  final TransformationController _transformationController =
      TransformationController();
  // Created eagerly: a lazy `late` first read in dispose() would create the
  // ticker on an already deactivated element.
  late final AnimationController _zoomController;
  Animation<Matrix4>? _zoomAnimation;
  Offset _doubleTapPosition = Offset.zero;
  int _pointerCount = 0;

  @override
  void initState() {
    super.initState();
    _zoomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _zoomController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    final bool isZoomed =
        _transformationController.value.getMaxScaleOnAxis() > 1.01;
    const double zoomScale = 2.5;
    final Matrix4 target = isZoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
            ..translateByDouble(
              -_doubleTapPosition.dx * (zoomScale - 1),
              -_doubleTapPosition.dy * (zoomScale - 1),
              0,
              1,
            )
            ..scaleByDouble(zoomScale, zoomScale, 1, 1));

    _zoomAnimation?.removeListener(_onZoomTick);
    _zoomAnimation =
        Matrix4Tween(
            begin: _transformationController.value,
            end: target,
          ).animate(
            CurvedAnimation(parent: _zoomController, curve: Curves.easeOut),
          )
          ..addListener(_onZoomTick);
    _zoomController.forward(from: 0);
  }

  void _onZoomTick() {
    _transformationController.value = _zoomAnimation!.value;
    _updateZoomState();
  }

  void _updateZoomState() {
    final bool isZoomed =
        _pointerCount >= 2 ||
        _transformationController.value.getMaxScaleOnAxis() > 1.01;
    widget.onZoomStateChanged(isZoomed);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        _pointerCount++;
        _updateZoomState();
      },
      onPointerUp: (_) {
        _pointerCount = (_pointerCount - 1).clamp(0, 10);
        _updateZoomState();
      },
      onPointerCancel: (_) {
        _pointerCount = (_pointerCount - 1).clamp(0, 10);
        _updateZoomState();
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTapDown: (details) =>
            _doubleTapPosition = details.localPosition,
        onDoubleTap: _handleDoubleTap,
        child: InteractiveViewer(
          transformationController: _transformationController,
          minScale: 1,
          maxScale: 4,
          onInteractionEnd: (_) => _updateZoomState(),
          child: Center(
            child: Image(
              image: widget.item.imageProvider,
              fit: BoxFit.contain,
              // Its thumbnail until it's ready, so that there's something to
              // zoom out of the post while it decodes.
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                final Size? size = _thumbnailSize(context);
                if (frame != null || wasSynchronouslyLoaded || size == null) {
                  return child;
                }
                return SizedBox.fromSize(
                  size: size,
                  child: Image(
                    image: widget.item.thumbnail!,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                );
              },
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) {
                  return child;
                }

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    child,
                    const CupertinoActivityIndicator(
                      radius: 14,
                      color: Colors.white,
                    ),
                  ],
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return const Text(
                  'Unable to load image',
                  style: TextStyle(color: Colors.white),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the viewer's controls only once its route has (nearly) finished
/// opening, and hides them as soon as it starts closing, so they don't
/// sit under the video zooming in and out of its post.
class RouteChromeFade extends StatelessWidget {
  const RouteChromeFade({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Animation<double>? route = ModalRoute.of(context)?.animation;
    if (route == null) {
      return child;
    }
    return AnimatedBuilder(
      animation: route,
      child: child,
      builder: (context, child) => Opacity(
        opacity: ((route.value - 0.7) / 0.3).clamp(0.0, 1.0),
        child: child,
      ),
    );
  }
}

/// A route that opens the viewer by zooming its media out of somewhere
/// (like the inline video it was opened from). Only the media layer zooms;
/// the background fades in place, and the controls fade in at the end
/// ([RouteChromeFade]). Both keep the same widgets throughout, so the
/// viewer isn't rebuilt mid-transition.
abstract interface class MediaZoomTransition {
  Widget buildMediaZoom(BuildContext context, Widget media);

  Widget buildBackgroundFade(BuildContext context, Widget background);
}
