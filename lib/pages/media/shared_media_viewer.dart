import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:liquid_glass_widgets/widgets/containers/glass_card.dart';
import 'package:liquid_glass_widgets/widgets/interactive/glass_button.dart';
import 'package:liquid_glass_widgets/widgets/interactive/glass_chip.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

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
    this.actions,
    this.onIndexChanged,
  }) : super(key: key);

  final List<SharedMediaViewerItem> items;
  final int initialIndex;
  final VoidCallback onClose;
  final SharedMediaViewerTopBarActions? actions;
  final ValueChanged<int>? onIndexChanged;

  @override
  State<SharedMediaViewer> createState() => _SharedMediaViewerState();
}

class _SharedMediaViewerState extends State<SharedMediaViewer> {
  late final PageController _pageController;
  late final Player _viewerPlayer;
  late final VideoController _viewerController;
  late int _currentIndex;
  bool _isVideoScrubbing = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = _sanitizeIndex(widget.initialIndex, widget.items.length);
    _pageController = PageController(initialPage: _currentIndex);
    _viewerPlayer = Player();
    _viewerController = VideoController(_viewerPlayer);
    _viewerPlayer.setPlaylistMode(PlaylistMode.loop);
    _viewerPlayer.setVolume(100.0);
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
    _viewerPlayer.dispose();
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildPagedBackdrop()),
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
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
                  player: _viewerPlayer,
                  controller: _viewerController,
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
                GlassButton(
                  icon: const Icon(CupertinoIcons.back),
                  onTap: widget.onClose,
                  width: 36,
                  height: 36,
                  iconSize: 18,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final SharedMediaViewerAction action in actions) ...[
                      _buildActionButton(action),
                      const SizedBox(width: 8),
                    ],

                    GlassChip(
                      label: itemCount == 0
                          ? '0 / 0'
                          : '${_currentIndex + 1} / $itemCount',
                      iconSize: 18,
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

  Widget _buildActionButton(SharedMediaViewerAction action) {
    final bool disableForBusy = action.isBusy && action.disableWhenBusy;
    final bool disableForCompleted =
        action.isCompleted && action.disableWhenCompleted;
    final VoidCallback? onPressed = (disableForBusy || disableForCompleted)
        ? null
        : action.onPressed;

    return GlassButton(
      icon: action.isBusy
          ? const CupertinoActivityIndicator(radius: 9)
          : Icon(
              action.isCompleted && action.completedIcon != null
                  ? action.completedIcon!
                  : action.icon,
              color: Colors.white,
              size: 18,
            ),
      onTap: onPressed ?? () {},
      width: 36,
      height: 36,
      iconSize: 18,
    );
  }
}

class _SharedMediaVideoPage extends StatefulWidget {
  const _SharedMediaVideoPage({
    Key? key,
    required this.item,
    required this.player,
    required this.controller,
    required this.isActive,
    required this.onScrubStateChanged,
    this.thumbnail,
  }) : super(key: key);

  final SharedMediaViewerItem item;
  final Player player;
  final VideoController controller;
  final bool isActive;
  final ValueChanged<bool> onScrubStateChanged;
  final ImageProvider<Object>? thumbnail;

  @override
  State<_SharedMediaVideoPage> createState() => _SharedMediaVideoPageState();
}

class _SharedMediaVideoPageState extends State<_SharedMediaVideoPage> {
  static const double _backSwipeEdgeInset = 24;

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
  double _dragSeekPreviewMs = 0;
  bool _isHorizontalSeeking = false;

  @override
  void initState() {
    super.initState();

    if (widget.isActive) {
      _attachSubscriptions();
      _openAndPlay();
    }
  }

  @override
  void didUpdateWidget(covariant _SharedMediaVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.item.id != widget.item.id) {
      _cancelSubscriptions();
      _resetPlaybackState();
      if (widget.isActive) {
        _attachSubscriptions();
        _openAndPlay();
      }
      return;
    }

    if (!oldWidget.isActive && widget.isActive) {
      _attachSubscriptions();
      _openAndPlay();
    } else if (oldWidget.isActive && !widget.isActive) {
      widget.player.pause();
      _cancelSubscriptions();
      _resetPlaybackState();
    }
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    super.dispose();
  }

  void _attachSubscriptions() {
    _cancelSubscriptions();

    _playingSub = widget.player.stream.playing.listen((playing) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isPlaying = playing;
      });
    });
    _positionSub = widget.player.stream.position.listen((position) {
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
    _durationSub = widget.player.stream.duration.listen((duration) {
      if (!mounted) {
        return;
      }

      setState(() => _duration = duration);
    });
    _bufferingSub = widget.player.stream.buffering.listen((buffering) {
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

  void _resetPlaybackState() {
    setState(() {
      _isPlaying = false;
      _isBuffering = false;
      _hasVideoFrame = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      _isHorizontalSeeking = false;
    });
  }

  Future<void> _openAndPlay() async {
    final String snapshotSource = widget.item.source;
    final MediaSourceResolver? resolveSource = widget.item.resolveVideoSource;
    if (resolveSource == null) {
      return;
    }

    try {
      final String resolvedSource = await resolveSource(snapshotSource);
      if (!mounted ||
          !widget.isActive ||
          widget.item.source != snapshotSource) {
        return;
      }

      await widget.player.open(Media(resolvedSource), play: false);
      if (!mounted || !widget.isActive) {
        return;
      }

      if (!mounted || !widget.isActive) {
        return;
      }

      await widget.player.play();
    } catch (error) {
      // ignore: empty_catches
    }
  }

  Future<void> _togglePlayPause() async {
    await widget.player.playOrPause();
  }

  Future<void> _seekTo(double value) async {
    try {
      await widget.player.seek(
        _clampDuration(Duration(milliseconds: value.round())),
      );
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

  void _handleScrubPanStart(DragStartDetails details) {
    if (details.globalPosition.dx <= _backSwipeEdgeInset) {
      return;
    }

    if (_duration <= Duration.zero) {
      return;
    }

    _dragSeekPreviewMs = _position.inMilliseconds.toDouble();
    setState(() {
      _isHorizontalSeeking = true;
    });
    widget.onScrubStateChanged(true);
  }

  void _handleScrubPanUpdate(DragUpdateDetails details) {
    if (!_isHorizontalSeeking) {
      return;
    }

    final double width =
        MediaQuery.of(context).size.width - _backSwipeEdgeInset;
    if (width <= 0) {
      return;
    }

    final double durationMs = _duration.inMilliseconds.toDouble();
    if (durationMs <= 0) {
      return;
    }

    final double msPerScreen = durationMs.clamp(15000.0, 90000.0);
    _dragSeekPreviewMs += details.delta.dx / width * msPerScreen;
    _dragSeekPreviewMs = _dragSeekPreviewMs.clamp(0.0, durationMs);
    setState(() {});
  }

  Future<void> _handleScrubPanEnd(DragEndDetails details) async {
    if (!_isHorizontalSeeking) {
      return;
    }

    final Duration target = _clampDuration(
      Duration(milliseconds: _dragSeekPreviewMs.round()),
    );
    setState(() {
      _isHorizontalSeeking = false;
    });
    widget.onScrubStateChanged(false);
    await _seekTo(target.inMilliseconds.toDouble());
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
        if (widget.isActive)
          Positioned.fill(
            child: StreamBuilder<int?>(
              stream: widget.player.stream.width,
              builder: (context, widthSnapshot) {
                return StreamBuilder<int?>(
                  stream: widget.player.stream.height,
                  builder: (context, heightSnapshot) {
                    final int width = widthSnapshot.data ?? 0;
                    final int height = heightSnapshot.data ?? 0;
                    final bool hasValidDimensions = width > 0 && height > 0;
                    final double aspectRatio = hasValidDimensions
                        ? width / height
                        : 16 / 9;

                    final bool showVideo =
                        hasValidDimensions && _hasVideoFrame && !_isBuffering;

                    return Stack(
                      children: [
                        AnimatedOpacity(
                          opacity: showVideo ? 1 : 0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: aspectRatio,
                              child: Video(
                                controller: widget.controller,
                                controls: NoVideoControls,
                                fit: BoxFit.fill,
                              ),
                            ),
                          ),
                        ),

                        AnimatedOpacity(
                          opacity: showVideo ? 0 : 1,
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
        if (_isHorizontalSeeking)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '${_formatDuration(_clampDuration(Duration(milliseconds: _dragSeekPreviewMs.round())))} / ${_formatDuration(_duration)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        Positioned.fill(
          left: _backSwipeEdgeInset,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: _handleScrubPanStart,
            onPanUpdate: _handleScrubPanUpdate,
            onPanEnd: _handleScrubPanEnd,
            onPanCancel: () {
              if (_isHorizontalSeeking) {
                widget.onScrubStateChanged(false);
                setState(() {
                  _isHorizontalSeeking = false;
                });
              }
            },
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                      value: _position.inMilliseconds.toDouble().clamp(
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
                    '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
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
