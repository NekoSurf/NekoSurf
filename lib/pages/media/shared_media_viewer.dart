import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/widgets/feed_player_recycler.dart';
import 'package:flutter_chan/widgets/video_scrub_gesture.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:preload_page_view/preload_page_view.dart';

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

class SharedMediaViewerTopBarActions {
  const SharedMediaViewerTopBarActions({
    this.saveToggle,
    this.download,
    this.share,
  });

  final SharedMediaViewerSaveToggleAction? saveToggle;
  final SharedMediaViewerDownloadAction? download;
  final SharedMediaViewerShareAction? share;
}

class SharedMediaViewerAction {
  const SharedMediaViewerAction({
    required this.icon,
    required this.onPressed,
    this.completedIcon,
    this.isBusy = false,
    this.isCompleted = false,
    this.disableWhenBusy = true,
    this.disableWhenCompleted = false,
  });

  final IconData icon;
  final IconData? completedIcon;
  final VoidCallback? onPressed;
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
  late final PreloadPageController _pageController;
  String? _handoffItemId;
  late int _currentIndex;
  bool _isVideoScrubbing = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = _sanitizeIndex(widget.initialIndex, widget.items.length);
    _pageController = PreloadPageController(initialPage: _currentIndex);
    if (widget.handoff != null && widget.items.isNotEmpty) {
      _handoffItemId = widget.items[_currentIndex].id;
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
    final double topInset = MediaQuery.of(context).padding.top;
    final int itemCount = widget.items.length;
    final List<SharedMediaViewerAction> actions = itemCount == 0
        ? const <SharedMediaViewerAction>[]
        : _buildActions();
    final String mediaTitle = _resolveMediaTitle(itemCount);

    void showFileInfo() {
      showCupertinoDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('File Information'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Filename: $mediaTitle'),
          ),
          actions: [
            CupertinoDialogAction(
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
          PreloadPageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            preloadPagesCount: 3,
            physics: _isVideoScrubbing
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            itemCount: itemCount,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
                _isVideoScrubbing = false;
              });
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
                  thumbnail: item.thumbnail,
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
              );
            },
          ),
          Positioned(
            top: topInset + 8,
            left: 8,
            right: 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _OverlayButton(
                  onPressed: widget.onClose,
                  child: const Icon(
                    CupertinoIcons.back,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: showFileInfo,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        mediaTitle,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final SharedMediaViewerAction action in actions) ...[
                      _buildActionButton(action),
                      const SizedBox(width: 8),
                    ],

                    _OverlayButton(
                      onPressed: showFileInfo,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        itemCount == 0
                            ? '0 / 0'
                            : '${_currentIndex + 1} / $itemCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
    final VoidCallback? onPressed = (disableForBusy || disableForCompleted)
        ? null
        : action.onPressed;

    return _OverlayButton(
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
    this.padding = EdgeInsets.zero,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: padding,
      minimumSize: const Size(36, 36),
      color: Colors.black.withValues(alpha: 0.45),
      disabledColor: Colors.black.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(18),
      onPressed: onPressed,
      child: child,
    );
  }
}

class _SharedMediaVideoPage extends StatefulWidget {
  const _SharedMediaVideoPage({
    Key? key,
    required this.item,
    required this.isActive,
    required this.onScrubStateChanged,
    this.handoff,
    this.recycler,
    this.thumbnail,
  }) : super(key: key);

  final SharedMediaViewerItem item;
  final RecycledPlayer? handoff;
  final FeedPlayerRecycler? recycler;
  final bool isActive;
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

  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _hasVideoFrame = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
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
      final RecycledPlayer leased = recycler.acquire();
      _leased = leased;
      _player = leased.player;
      _controller = leased.controller;
    } else {
      _ownsPlayer = true;
      _player = Player();
      _controller = VideoController(_player);
    }

    _attachSubscriptions();
    _load();
  }

  @override
  void didUpdateWidget(covariant _SharedMediaVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!oldWidget.isActive && widget.isActive) {
      _player.play().catchError((_) {});
    } else if (oldWidget.isActive && !widget.isActive) {
      _player.pause().catchError((_) {});
    }
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
  }

  void _cancelSubscriptions() {
    _errorSub?.cancel();
    _playingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferingSub?.cancel();
    _errorSub = null;
    _playingSub = null;
    _positionSub = null;
    _durationSub = null;
    _bufferingSub = null;
  }

  bool _isItemLoaded() {
    final Playlist playlist = _player.state.playlist;
    final int index = playlist.index;
    return index >= 0 &&
        index < playlist.medias.length &&
        playlist.medias[index].uri == widget.item.source;
  }

  /// Opens the media paused; it only plays while the page is active.
  Future<void> _load() async {
    final String source = widget.item.source;
    final MediaSourceResolver? resolveSource = widget.item.resolveVideoSource;

    try {
      // Handed-off players already have this media open.
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

      await _player.setPlaylistMode(PlaylistMode.loop);
      await _player.setVolume(100.0);
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

  Future<void> _togglePlayPause() async {
    await _player.playOrPause();
  }

  Future<void> _seekTo(double value) async {
    try {
      await _player.seek(_clampDuration(Duration(milliseconds: value.round())));
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
    return Stack(
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

                    final bool showVideo =
                        hasValidDimensions && _hasVideoFrame && !_isBuffering;
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
                          opacity: widget.isActive && !showVideo ? 1 : 0,
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(28, 28),
                    onPressed: _togglePlayPause,
                    child: Icon(
                      _isPlaying
                          ? CupertinoIcons.pause_fill
                          : CupertinoIcons.play_fill,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: _displayPosition.inMilliseconds.toDouble().clamp(
                        0,
                        (_duration.inMilliseconds <= 0
                                ? 1
                                : _duration.inMilliseconds)
                            .toDouble(),
                      ),
                      min: 0,
                      max:
                          (_duration.inMilliseconds <= 0
                                  ? 1
                                  : _duration.inMilliseconds)
                              .toDouble(),
                      onChanged: _duration.inMilliseconds > 0 ? _seekTo : null,
                      activeColor: Colors.white,
                      inactiveColor: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
                  Text(
                    '${_formatDuration(_displayPosition)} / ${_formatDuration(_duration)}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SharedMediaImagePage extends StatelessWidget {
  const _SharedMediaImagePage({Key? key, required this.item}) : super(key: key);

  final SharedMediaViewerItem item;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 1,
      maxScale: 4,
      child: Center(
        child: Image(
          image: item.imageProvider,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              return child;
            }

            return const Center(child: CupertinoActivityIndicator(radius: 14));
          },
          errorBuilder: (context, error, stackTrace) {
            return const Text(
              'Unable to load image',
              style: TextStyle(color: Colors.white),
            );
          },
        ),
      ),
    );
  }
}
