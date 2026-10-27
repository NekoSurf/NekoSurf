import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:flutter_chan/widgets/dash_dialogs.dart';
import 'package:flutter_chan/widgets/feed_player_recycler.dart';
import 'package:flutter_chan/widgets/video_scrub_gesture.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:preload_page_view/preload_page_view.dart';
import 'package:provider/provider.dart';

typedef MediaSourceResolver = Future<String> Function(String source);

class SharedMediaViewerSaveToggleAction {
  const SharedMediaViewerSaveToggleAction({
    required this.isSaved,
    required this.isSaving,
    required this.isRemoving,
    required this.didSave,
    required this.onSave,
    required this.onRemove,
  });

  final bool isSaved;
  final bool isSaving;
  final bool isRemoving;
  final bool didSave;
  final VoidCallback onSave;
  final VoidCallback onRemove;
}

class SharedMediaViewerDownloadAction {
  const SharedMediaViewerDownloadAction({
    required this.isDownloading,
    required this.didDownload,
    required this.onDownload,
  });

  final bool isDownloading;
  final bool didDownload;
  final VoidCallback onDownload;
}

class SharedMediaViewerShareAction {
  const SharedMediaViewerShareAction({
    required this.isSharing,
    required this.onShare,
  });

  final bool isSharing;
  final VoidCallback onShare;
}

class SharedMediaViewerSearchAction {
  const SharedMediaViewerSearchAction({required this.onSearch});

  /// Gets the button's context, to anchor a menu to it.
  final ValueChanged<BuildContext> onSearch;
}

class SharedMediaViewerTopBarActions {
  const SharedMediaViewerTopBarActions({
    this.saveToggle,
    this.download,
    this.share,
    this.search,
  });

  final SharedMediaViewerSaveToggleAction? saveToggle;
  final SharedMediaViewerDownloadAction? download;
  final SharedMediaViewerShareAction? share;
  final SharedMediaViewerSearchAction? search;
}

class SharedMediaViewerAction {
  const SharedMediaViewerAction({
    required this.icon,
    required this.onPressed,
    this.onPressedWithContext,
    this.completedIcon,
    this.isBusy = false,
    this.isCompleted = false,
    this.disableWhenBusy = true,
    this.disableWhenCompleted = false,
  });

  final IconData icon;
  final IconData? completedIcon;
  final VoidCallback? onPressed;

  /// Used instead of [onPressed] when the action needs the button's context.
  final ValueChanged<BuildContext>? onPressedWithContext;
  final bool isBusy;
  final bool isCompleted;
  final bool disableWhenBusy;
  final bool disableWhenCompleted;
}

class SharedMediaViewerItem {
  const SharedMediaViewerItem({
    required this.id,
    required this.source,
    required this.isVideo,
    required this.imageProvider,
    this.resolveVideoSource,
    this.thumbnail,
  });

  final String id;
  final String source;
  final bool isVideo;
  final ImageProvider<Object> imageProvider;
  final MediaSourceResolver? resolveVideoSource;
  final ImageProvider<Object>? thumbnail;
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
    Key? key,
    required this.items,
    required this.initialIndex,
    required this.onClose,
    this.mediaName,
    this.mediaNameBuilder,
    this.actions,
    this.onIndexChanged,
    this.handoff,
    this.recycler,
  }) : super(key: key);

  final List<SharedMediaViewerItem> items;
  final int initialIndex;
  final VoidCallback onClose;
  final SharedMediaViewerTopBarActions? actions;
  final ValueChanged<int>? onIndexChanged;

  /// Player already showing the initial item; owned by the caller.
  final RecycledPlayer? handoff;

  /// Source of players for video pages; without it each page creates its own.
  final FeedPlayerRecycler? recycler;

  final String? mediaName;
  final String Function(int index)? mediaNameBuilder;

  @override
  State<SharedMediaViewer> createState() => _SharedMediaViewerState();
}

class _SharedMediaViewerState extends State<SharedMediaViewer> {
  static const int _precacheRadius = 3;

  late final PreloadPageController _pageController;
  String? _handoffItemId;
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
    if (widget.handoff != null && widget.items.isNotEmpty) {
      _handoffItemId = widget.items[_currentIndex].id;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _precacheAround(_currentIndex);
      }
    });
  }

  /// Only one page per side is built, so every video page holds a live
  /// player. Images further out are still warmed up so paging stays smooth.
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
    final List<SharedMediaViewerAction> actions = itemCount == 0
        ? const <SharedMediaViewerAction>[]
        : _buildActions();
    final String mediaTitle = _resolveMediaTitle(itemCount);

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
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildPagedBackdrop()),
          // Android's smaller platform touch slop lets page drags beat pinch-to-zoom.
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
                widget.onIndexChanged?.call(index);
              },
              itemBuilder: (context, index) {
                final SharedMediaViewerItem item = widget.items[index];

                if (item.isVideo) {
                  return _SharedMediaVideoPage(
                    key: ValueKey('shared-media-video-${item.id}'),
                    item: item,
                    handoff: item.id == _handoffItemId ? widget.handoff : null,
                    recycler: widget.recycler,
                    isActive: _currentIndex == index,
                    chromeVisible: _chromeVisible,
                    onTap: _toggleChrome,
                    thumbnail: item.thumbnail,
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
          _chrome(
            top: true,
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
                  if (actions.isNotEmpty)
                    _ActionPill(
                      children: [
                        for (final SharedMediaViewerAction action in actions)
                          _buildActionButton(action),
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

  Widget _chrome({required bool top, required Widget child}) {
    return Positioned(
      top: top ? 0 : null,
      bottom: top ? null : 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !_chromeVisible,
        child: AnimatedSlide(
          offset: Offset(0, _chromeVisible ? 0 : (top ? -0.3 : 0.3)),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: _chromeVisible ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: child,
          ),
        ),
      ),
    );
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

        final ImageProvider<Object> lowerImage =
            _backdropForIndex(lower) ?? widget.items[lower].imageProvider;
        final ImageProvider<Object> upperImage =
            _backdropForIndex(upper) ?? widget.items[upper].imageProvider;

        return Stack(
          fit: StackFit.expand,
          children: [
            _buildBlurredBackdrop(lowerImage, upper == lower ? 1 : 1 - t),
            if (upper != lower) _buildBlurredBackdrop(upperImage, t),
          ],
        );
      },
    );
  }

  ImageProvider<Object>? _backdropForIndex(int index) {
    if (index < 0 || index >= widget.items.length) {
      return null;
    }

    final SharedMediaViewerItem item = widget.items[index];
    return item.thumbnail ?? item.imageProvider;
  }

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

  List<SharedMediaViewerAction> _buildActions() {
    final SharedMediaViewerTopBarActions? actionConfig = widget.actions;
    if (actionConfig == null) {
      return const <SharedMediaViewerAction>[];
    }

    final List<SharedMediaViewerAction> actions = <SharedMediaViewerAction>[];
    final SharedMediaViewerSaveToggleAction? saveToggle =
        actionConfig.saveToggle;
    if (saveToggle != null) {
      if (saveToggle.isSaved) {
        actions.add(
          SharedMediaViewerAction(
            icon: CupertinoIcons.trash,
            onPressed: saveToggle.onRemove,
            isBusy: saveToggle.isRemoving,
          ),
        );
      } else {
        actions.add(
          SharedMediaViewerAction(
            icon: CupertinoIcons.add_circled,
            completedIcon: CupertinoIcons.check_mark_circled_solid,
            onPressed: saveToggle.onSave,
            isBusy: saveToggle.isSaving,
            isCompleted: saveToggle.didSave,
            disableWhenCompleted: true,
          ),
        );
      }
    }

    final SharedMediaViewerDownloadAction? download = actionConfig.download;
    if (download != null) {
      actions.add(
        SharedMediaViewerAction(
          icon: CupertinoIcons.arrow_down_to_line,
          completedIcon: CupertinoIcons.check_mark_circled_solid,
          onPressed: download.onDownload,
          isBusy: download.isDownloading,
          isCompleted: download.didDownload,
          disableWhenCompleted: true,
        ),
      );
    }

    final SharedMediaViewerShareAction? share = actionConfig.share;
    if (share != null) {
      actions.add(
        SharedMediaViewerAction(
          icon: CupertinoIcons.share,
          onPressed: share.onShare,
          isBusy: share.isSharing,
        ),
      );
    }

    final SharedMediaViewerSearchAction? search = actionConfig.search;
    if (search != null) {
      actions.add(
        SharedMediaViewerAction(
          icon: CupertinoIcons.search,
          onPressed: null,
          onPressedWithContext: search.onSearch,
        ),
      );
    }

    return actions;
  }

  String _resolveMediaTitle(int itemCount) {
    if (itemCount == 0) {
      return '';
    }

    final String Function(int index)? builder = widget.mediaNameBuilder;
    if (builder != null) {
      return builder(_currentIndex);
    }

    return widget.mediaName ?? '';
  }

  Widget _buildActionButton(SharedMediaViewerAction action) {
    final bool disableForBusy = action.isBusy && action.disableWhenBusy;
    final bool disableForCompleted =
        action.isCompleted && action.disableWhenCompleted;
    final bool disabled = disableForBusy || disableForCompleted;
    final ValueChanged<BuildContext>? withContext = action.onPressedWithContext;
    if (withContext != null) {
      return Builder(
        builder: (buttonContext) => _OverlayButton(
          bare: true,
          onPressed: disabled ? null : () => withContext(buttonContext),
          child: Icon(action.icon, color: Colors.white, size: 18),
        ),
      );
    }

    final VoidCallback? onPressed = disabled ? null : action.onPressed;

    return _OverlayButton(
      bare: true,
      onPressed: onPressed,
      child: action.isBusy
          ? const CupertinoActivityIndicator(radius: 9)
          : Icon(
              action.isCompleted && action.completedIcon != null
                  ? action.completedIcon!
                  : action.icon,
              color: Colors.white,
              size: 18,
            ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.onPressed,
    required this.child,
    this.bare = false,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final Widget button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: bare
            ? null
            : BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
        child: Opacity(opacity: onPressed == null ? 0.5 : 1, child: child),
      ),
    );

    if (bare) {
      return button;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: button,
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

class _SharedMediaVideoPage extends StatefulWidget {
  const _SharedMediaVideoPage({
    Key? key,
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
    this.handoff,
    this.recycler,
    this.thumbnail,
  }) : super(key: key);

  final double rate;
  final VoidCallback onCycleRate;
  final bool autoAdvance;
  final VoidCallback onToggleAutoAdvance;

  /// The video reached its end; only fires with [autoAdvance] on.
  final VoidCallback onCompleted;
  final SharedMediaViewerItem item;
  final RecycledPlayer? handoff;
  final FeedPlayerRecycler? recycler;
  final bool isActive;
  final bool chromeVisible;
  final VoidCallback onTap;
  final ValueChanged<bool> onScrubStateChanged;
  final ImageProvider<Object>? thumbnail;

  @override
  State<_SharedMediaVideoPage> createState() => _SharedMediaVideoPageState();
}

class _SharedMediaVideoPageState extends State<_SharedMediaVideoPage> {
  late final Player _player;
  late final VideoController _controller;
  RecycledPlayer? _leased;
  bool _ownsPlayer = false;

  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<Duration>? _bufferSub;
  StreamSubscription<bool>? _completedSub;

  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _hasVideoFrame = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  Duration? _scrubPreview;

  Duration get _displayPosition => _scrubPreview ?? _position;
  @override
  void initState() {
    super.initState();

    final RecycledPlayer? handoff = widget.handoff;
    final FeedPlayerRecycler? recycler = widget.recycler;
    if (handoff != null) {
      _player = handoff.player;
      _controller = handoff.controller;
    } else if (recycler != null) {
      // A recently released player may still hold this video.
      final RecycledPlayer leased = recycler.acquire(url: widget.item.source);
      _leased = leased;
      _player = leased.player;
      _controller = leased.controller;
    } else {
      _ownsPlayer = true;
      _player = createMediaPlayer();
      _controller = VideoController(_player);
    }

    _attachSubscriptions();
    _load();
  }

  @override
  void didUpdateWidget(covariant _SharedMediaVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!oldWidget.isActive && widget.isActive) {
      unawaited(_resume());
    } else if (oldWidget.isActive && !widget.isActive) {
      _player.pause().catchError((_) {});
    }

    if (oldWidget.rate != widget.rate) {
      _player.setRate(widget.rate).catchError((_) {});
    }
    if (oldWidget.autoAdvance != widget.autoAdvance) {
      _player.setPlaylistMode(_playlistMode).catchError((_) {});
    }
  }

  PlaylistMode get _playlistMode =>
      widget.autoAdvance ? PlaylistMode.none : PlaylistMode.loop;

  Future<void> _resume() async {
    try {
      await _player.setRate(widget.rate);
      // With auto-advance a finished video stays at its end; start it over
      // when paging back to it.
      if (_player.state.completed) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    } catch (_) {}
  }

  @override
  void dispose() {
    _cancelSubscriptions();

    final RecycledPlayer? leased = _leased;
    if (leased != null) {
      unawaited(widget.recycler!.release(leased));
    } else if (_ownsPlayer) {
      unawaited(_player.dispose());
    }
    super.dispose();
  }

  void _attachSubscriptions() {
    _cancelSubscriptions();

    if (_isItemLoaded()) {
      final PlayerState state = _player.state;
      _isPlaying = state.playing;
      _isBuffering = state.buffering;
      _position = state.position;
      _duration = state.duration;
      _buffer = state.buffer;
      _hasVideoFrame = state.position > const Duration(milliseconds: 100);
    }

    _playingSub = _player.stream.playing.listen((playing) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isPlaying = playing;
      });
    });
    _positionSub = _player.stream.position.listen((position) {
      if (!mounted) {
        return;
      }

      final bool gotFrame =
          !_hasVideoFrame && position > const Duration(milliseconds: 100);

      setState(() {
        _position = position;
        if (gotFrame) {
          _hasVideoFrame = true;
        }
      });
    });
    _durationSub = _player.stream.duration.listen((duration) {
      if (!mounted) {
        return;
      }

      setState(() => _duration = duration);
    });
    _bufferingSub = _player.stream.buffering.listen((buffering) {
      if (!mounted) {
        return;
      }

      setState(() => _isBuffering = buffering);
    });
    _bufferSub = _player.stream.buffer.listen((buffer) {
      if (!mounted) {
        return;
      }

      setState(() => _buffer = buffer);
    });
    _completedSub = _player.stream.completed.listen((completed) {
      if (mounted && completed && widget.isActive && widget.autoAdvance) {
        widget.onCompleted();
      }
    });
  }

  void _cancelSubscriptions() {
    _errorSub?.cancel();
    _playingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferingSub?.cancel();
    _bufferSub?.cancel();
    _completedSub?.cancel();
    _errorSub = null;
    _playingSub = null;
    _positionSub = null;
    _durationSub = null;
    _bufferingSub = null;
    _bufferSub = null;
    _completedSub = null;
  }

  bool _isItemLoaded() => playerHasMedia(_player, widget.item.source);

  /// Opens the media paused; it only plays while the page is active.
  ///
  /// Once disposed, a leased player is back in the recycler and may already
  /// belong to another page or feed post, so every step re-checks [mounted]
  /// before touching it.
  Future<void> _load() async {
    final String source = widget.item.source;
    final MediaSourceResolver? resolveSource = widget.item.resolveVideoSource;

    try {
      // Handed-off and matching recycled players already have it open.
      if (!_isItemLoaded()) {
        final String resolvedSource = resolveSource == null
            ? source
            : await resolveSource(source);
        if (!mounted) {
          return;
        }

        await _player.open(Media(resolvedSource), play: false);
        if (!mounted) {
          return;
        }

        // Recycled players don't re-emit an unchanged duration.
        setState(() => _duration = _player.state.duration);
      }

      await _player.setPlaylistMode(_playlistMode);
      if (!mounted) {
        return;
      }
      await _player.setRate(widget.rate);
      if (!mounted) {
        return;
      }
      await _player.setVolume(100.0);
      if (!mounted) {
        return;
      }
      // Recycled feed players may still have audio disabled.
      await _player.setAudioTrack(AudioTrack.auto());
      if (!mounted) {
        return;
      }

      if (widget.isActive) {
        await _player.play();
      } else {
        await _player.pause();
      }
    } catch (_) {}
  }

  String _formatRate(double rate) {
    final String text = rate == rate.roundToDouble()
        ? rate.toStringAsFixed(0)
        : rate.toString();
    return '$text×';
  }

  Future<void> _togglePlayPause() async {
    await _player.playOrPause();
  }

  // Seeking on every drag update floods the player with seeks and keeps it
  // buffering; drags only move the preview and seek once on release.
  void _previewSeek(double value) {
    setState(() {
      _scrubPreview = _clampDuration(Duration(milliseconds: value.round()));
    });
  }

  Future<void> _seekTo(double value) async {
    final Duration target = _clampDuration(
      Duration(milliseconds: value.round()),
    );
    // Show the target right away instead of snapping back to the old position.
    setState(() {
      _position = target;
      _scrubPreview = null;
    });
    try {
      await _player.seek(target);
    } catch (_) {
      // Ignore transient seek races.
    }
  }

  String _formatDuration(Duration value) {
    final int hours = value.inHours;
    final String minutes = value.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final String seconds = value.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }

    return '$minutes:$seconds';
  }

  Duration _clampDuration(Duration value) {
    if (_duration <= Duration.zero) {
      return value < Duration.zero ? Duration.zero : value;
    }

    if (value < Duration.zero) {
      return Duration.zero;
    }

    if (value > _duration) {
      return _duration;
    }

    return value;
  }

  @override
  void deactivate() {
    widget.onScrubStateChanged(false);
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: VideoScrubGesture(
              player: _player,
              onScrubStateChanged: widget.onScrubStateChanged,
              onPreviewChanged: (preview) {
                setState(() => _scrubPreview = preview);
              },
              child: StreamBuilder<int?>(
                stream: _player.stream.width,
                initialData: _player.state.width,
                builder: (context, widthSnapshot) {
                  return StreamBuilder<int?>(
                    stream: _player.stream.height,
                    initialData: _player.state.height,
                    builder: (context, heightSnapshot) {
                      final int width = widthSnapshot.data ?? 0;
                      final int height = heightSnapshot.data ?? 0;
                      final bool hasValidDimensions = width > 0 && height > 0;
                      final double aspectRatio = hasValidDimensions
                          ? width / height
                          : 16 / 9;

                      // Only wait for the first frame: hiding the video on
                      // every buffering blip (loops, seeks) makes it flicker
                      // back to the thumbnail.
                      final bool showVideo =
                          hasValidDimensions && _hasVideoFrame;
                      final ImageProvider<Object>? thumbnail = widget.thumbnail;

                      return Stack(
                        children: [
                          // Kept underneath so the video fades in over it.
                          if (thumbnail != null)
                            Positioned.fill(
                              child: Image(
                                image: thumbnail,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                              ),
                            ),

                          AnimatedOpacity(
                            opacity: showVideo ? 1 : 0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                            child: Center(
                              child: AspectRatio(
                                aspectRatio: aspectRatio,
                                child: Video(
                                  controller: _controller,
                                  controls: NoVideoControls,
                                  fit: BoxFit.fill,
                                ),
                              ),
                            ),
                          ),

                          AnimatedOpacity(
                            opacity:
                                widget.isActive && (!showVideo || _isBuffering)
                                ? 1
                                : 0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                            child: const Center(
                              child: CupertinoActivityIndicator(radius: 14),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !widget.chromeVisible,
              child: AnimatedSlide(
                offset: Offset(0, widget.chromeVisible ? 0 : 0.3),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: widget.chromeVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: _buildControls(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final double max =
        (_duration.inMilliseconds <= 0 ? 1 : _duration.inMilliseconds)
            .toDouble();

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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 18, 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _togglePlayPause,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: DashColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isPlaying
                          ? CupertinoIcons.pause_fill
                          : CupertinoIcons.play_fill,
                      color: Colors.black,
                      size: 17,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          activeTrackColor: DashColors.accent,
                          inactiveTrackColor: Colors.white.withValues(
                            alpha: 0.22,
                          ),
                          secondaryActiveTrackColor: Colors.white.withValues(
                            alpha: 0.45,
                          ),
                          thumbColor: Colors.white,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
                        child: Slider(
                          value: _displayPosition.inMilliseconds
                              .toDouble()
                              .clamp(0, max),
                          min: 0,
                          max: max,
                          // How far mpv has downloaded.
                          secondaryTrackValue: _buffer.inMilliseconds
                              .toDouble()
                              .clamp(0, max),
                          onChanged: _duration.inMilliseconds > 0
                              ? _previewSeek
                              : null,
                          onChangeEnd: _seekTo,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(_displayPosition),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _formatDuration(_duration),
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
                      color: widget.autoAdvance
                          ? DashColors.accent
                          : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SharedMediaImagePage extends StatefulWidget {
  const _SharedMediaImagePage({
    Key? key,
    required this.item,
    required this.onTap,
    required this.onZoomStateChanged,
  }) : super(key: key);

  final SharedMediaViewerItem item;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoomStateChanged;

  @override
  State<_SharedMediaImagePage> createState() => _SharedMediaImagePageState();
}

class _SharedMediaImagePageState extends State<_SharedMediaImagePage>
    with SingleTickerProviderStateMixin {
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
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) {
                  return child;
                }

                return const Center(
                  child: CupertinoActivityIndicator(radius: 14),
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
