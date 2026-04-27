import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/save_videos.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/saved_attachments_model.dart';
import 'package:flutter_chan/services/cached_video.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

// ---------------------------------------------------------------------------
// Entry page — vertical-swipe PageView over all media posts in a thread.
// Save/download buttons live in the top bar beside the index counter.
// ---------------------------------------------------------------------------
class ThreadMediaViewerPage extends StatefulWidget {
  const ThreadMediaViewerPage({
    Key? key,
    required this.mediaPosts,
    required this.initialIndex,
    required this.board,
    required this.thread,
    this.startPosition = Duration.zero,
  }) : super(key: key);

  final List<Post> mediaPosts;
  final int initialIndex;
  final String board;
  final int thread;
  final Duration startPosition;

  @override
  State<ThreadMediaViewerPage> createState() => _ThreadMediaViewerPageState();
}

class _ThreadMediaViewerPageState extends State<ThreadMediaViewerPage> {
  late final PageController _pageController;
  late int _currentIndex;
  bool _isVideoScrubbing = false;

  bool _isSaving = false;
  bool _isRemoving = false;
  bool _didSaveAttachment = false;
  Timer? _saveSuccessTimer;

  bool _isDownloading = false;
  bool _didDownload = false;
  Timer? _downloadSuccessTimer;
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _saveSuccessTimer?.cancel();
    _downloadSuccessTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Post get _currentPost => widget.mediaPosts[_currentIndex];

  bool _isVideo(Post post) =>
      post.ext == '.webm' || post.ext == '.mp4';

  String _mediaUrl(Post post) =>
      'https://i.4cdn.org/${widget.board}/${post.tim}${post.ext}';

  String _fileName(Post post) => '${post.tim}${post.ext}';

  Future<void> _saveToAttachments() async {
    if (_isSaving) return;
    final savedAttachments = context.read<SavedAttachmentsProvider>();
    final fileName = _fileName(_currentPost);
    final alreadySaved = savedAttachments.getSavedAttachments().any(
      (a) =>
          a.fileName?.split('/').last.split('.').first ==
          fileName.split('.').first,
    );
    if (alreadySaved) {
      _showSaveConfirmation();
      return;
    }
    setState(() {
      _isSaving = true;
    });
    await savedAttachments.addSavedAttachments(context, widget.board, fileName);
    if (!mounted) return;
    final saveSucceeded = savedAttachments.getSavedAttachments().any(
      (a) =>
          a.fileName?.split('/').last.split('.').first ==
          fileName.split('.').first,
    );
    setState(() {
      _isSaving = false;
    });
    if (saveSucceeded) {
      _showSaveConfirmation();
    }
  }

  Future<void> _removeFromAttachments() async {
    if (_isRemoving) return;
    setState(() {
      _isRemoving = true;
    });
    await context.read<SavedAttachmentsProvider>().removeSavedAttachments(
      _fileName(_currentPost),
      context,
    );
    if (!mounted) return;
    setState(() {
      _isRemoving = false;
    });
  }

  void _showSaveConfirmation() {
    _saveSuccessTimer?.cancel();
    setState(() {
      _didSaveAttachment = true;
    });
    _saveSuccessTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        _didSaveAttachment = false;
      });
    });
  }

  Future<void> _downloadToGallery() async {
    if (_isDownloading) return;
    final post = _currentPost;
    setState(() {
      _isDownloading = true;
    });
    await saveVideo(_mediaUrl(post), _fileName(post), context, isSaved: false);
    if (!mounted) return;
    setState(() {
      _isDownloading = false;
      _didDownload = true;
    });
    _downloadSuccessTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        _didDownload = false;
      });
    });
  }

  Future<void> _shareCurrentMedia() async {
    if (_isSharing) {
      return;
    }
    final post = _currentPost;
    setState(() {
      _isSharing = true;
    });
    await shareMedia(_mediaUrl(post), _fileName(post), context, isSaved: false);
    if (!mounted) {
      return;
    }
    setState(() {
      _isSharing = false;
    });
  }

  void _closeViewer() {
    Navigator.of(context).pop(_currentPost.no ?? _currentPost.tim);
  }

  Widget _buildSaveButton(BuildContext context) {
    final savedAttachments = context.watch<SavedAttachmentsProvider>();
    final fileName = _fileName(_currentPost);
    final isSaved = savedAttachments.getSavedAttachments().any(
      (a) =>
          a.fileName?.split('/').last.split('.').first ==
          fileName.split('.').first,
    );
    if (isSaved) {
      return CupertinoButton(
        minimumSize: const Size(36, 36),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(999),
        onPressed: _isRemoving ? null : _removeFromAttachments,
        child: _isRemoving
            ? const CupertinoActivityIndicator(radius: 9)
            : const Icon(CupertinoIcons.trash, color: Colors.white, size: 18),
      );
    }
    return CupertinoButton(
      minimumSize: const Size(36, 36),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: Colors.black.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(999),
      onPressed: _isSaving || _didSaveAttachment ? null : _saveToAttachments,
      child: _isSaving
          ? const CupertinoActivityIndicator(radius: 9)
          : Icon(
              _didSaveAttachment
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.add_circled,
              color: Colors.white,
              size: 18,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return PopScope<int>(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _closeViewer();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              physics: _isVideoScrubbing
                  ? const NeverScrollableScrollPhysics()
                  : const ClampingScrollPhysics(),
              itemCount: widget.mediaPosts.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                  _didSaveAttachment = false;
                  _didDownload = false;
                  _isVideoScrubbing = false;
                });
              },
              itemBuilder: (context, index) {
                final post = widget.mediaPosts[index];
                if (_isVideo(post)) {
                  return _ThreadMediaVideoPage(
                    key: ValueKey('thread-video-$index-${post.tim}'),
                    videoUrl: _mediaUrl(post),
                    isActive: _currentIndex == index,
                    onScrubStateChanged: (isScrubbing) {
                      if (!mounted || _isVideoScrubbing == isScrubbing) {
                        return;
                      }
                      setState(() {
                        _isVideoScrubbing = isScrubbing;
                      });
                    },
                    startPosition: index == widget.initialIndex
                        ? widget.startPosition
                        : Duration.zero,
                  );
                }
                return _ThreadMediaImagePage(
                  key: ValueKey('thread-image-$index-${post.tim}'),
                  imageUrl: _mediaUrl(post),
                );
              },
            ),
            // Top bar: [back] ... [save] [download] [N/total]
            Positioned(
              top: topInset + 8,
              left: 8,
              right: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    minimumSize: const Size(36, 36),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(999),
                    onPressed: _closeViewer,
                    child: const Icon(
                      CupertinoIcons.back,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Builder(builder: _buildSaveButton),
                      const SizedBox(width: 8),
                      CupertinoButton(
                        minimumSize: const Size(36, 36),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(999),
                        onPressed: _isDownloading || _didDownload
                            ? null
                            : _downloadToGallery,
                        child: _isDownloading
                            ? const CupertinoActivityIndicator(radius: 9)
                            : Icon(
                                _didDownload
                                    ? CupertinoIcons.check_mark_circled_solid
                                    : CupertinoIcons.arrow_down_to_line,
                                color: Colors.white,
                                size: 18,
                              ),
                      ),
                      const SizedBox(width: 8),
                      CupertinoButton(
                        minimumSize: const Size(36, 36),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(999),
                        onPressed: _isSharing ? null : _shareCurrentMedia,
                        child: _isSharing
                            ? const CupertinoActivityIndicator(radius: 9)
                            : const Icon(
                                CupertinoIcons.share,
                                color: Colors.white,
                                size: 18,
                              ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${_currentIndex + 1} / ${widget.mediaPosts.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
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
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Per-page video player — handles only playback and seek controls.
// ---------------------------------------------------------------------------
class _ThreadMediaVideoPage extends StatefulWidget {
  const _ThreadMediaVideoPage({
    Key? key,
    required this.videoUrl,
    required this.isActive,
    required this.onScrubStateChanged,
    this.startPosition = Duration.zero,
  }) : super(key: key);

  final String videoUrl;
  final bool isActive;
  final ValueChanged<bool> onScrubStateChanged;
  final Duration startPosition;

  @override
  State<_ThreadMediaVideoPage> createState() => _ThreadMediaVideoPageState();
}

class _ThreadMediaVideoPageState extends State<_ThreadMediaVideoPage> {
  static const double _backSwipeEdgeInset = 24;

  late final Player _player;
  late final VideoController _videoController;

  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _bufferingSub;

  String? _errorMessage;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isMuted = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _dragSeekPreviewMs = 0;
  bool _isHorizontalSeeking = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);

    _errorSub = _player.stream.error.listen((error) {
      if (!mounted) return;
      setState(() => _errorMessage = error);
    });
    _playingSub = _player.stream.playing.listen((playing) {
      if (!mounted) return;
      setState(() => _isPlaying = playing);
    });
    _positionSub = _player.stream.position.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });
    _durationSub = _player.stream.duration.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d);
    });
    _bufferingSub = _player.stream.buffering.listen((buffering) {
      if (!mounted) return;
      setState(() => _isBuffering = buffering);
    });

    if (widget.isActive) _openAndPlay();
  }

  @override
  void didUpdateWidget(covariant _ThreadMediaVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      _openAndPlay();
    } else if (oldWidget.isActive && !widget.isActive) {
      _player.pause().ignore();
    }
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _playingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferingSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  /// Mirrors the feed-player fix for media-kit #964: on iOS, explicitly
  /// selecting AudioTrack.auto() before play() prevents the player from doing a
  /// lazy AVAudioSession reconfiguration ~1 second into playback.
  Future<void> _applyAudioMode() async {
    try {
      if (Platform.isIOS && !_isMuted) {
        await _player.setAudioTrack(AudioTrack.auto());
      }
      await _player.setVolume(_isMuted ? 0 : 100);
    } catch (_) {
      // Ignore transient volume races.
    }
  }

  Future<void> _toggleMuted() async {
    setState(() => _isMuted = !_isMuted);
    await _applyAudioMode();
  }

  Future<void> _openAndPlay() async {
    try {
      final resolved = await resolveCachedVideoSource(widget.videoUrl);
      if (!mounted) return;
      await _player.setPlaylistMode(PlaylistMode.loop);
      await _player.open(Media(resolved), play: false);
      if (widget.startPosition > Duration.zero) {
        try {
          await _player.seek(widget.startPosition);
        } catch (_) {
          // Ignore seek races on open.
        }
      }
      if (!mounted) return;
      await _applyAudioMode();
      await _player.play();
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.toString());
    }
  }

  Future<void> _seekTo(double ms) async {
    try {
      await _player.seek(_clampDuration(Duration(milliseconds: ms.round())));
    } catch (_) {}
  }

  String _formatDuration(Duration v) {
    final h = v.inHours;
    final m = v.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = v.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
  }

  Duration _clampDuration(Duration v) {
    if (_duration <= Duration.zero)
      return v < Duration.zero ? Duration.zero : v;
    if (v < Duration.zero) return Duration.zero;
    if (v > _duration) return _duration;
    return v;
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
    final width = MediaQuery.of(context).size.width - _backSwipeEdgeInset;
    if (width <= 0) return;
    final durationMs = _duration.inMilliseconds.toDouble();
    if (durationMs <= 0) {
      return;
    }
    final msPerScreen = durationMs.clamp(15000.0, 90000.0);
    _dragSeekPreviewMs += details.delta.dx / width * msPerScreen;
    _dragSeekPreviewMs = _dragSeekPreviewMs.clamp(0.0, durationMs);
    setState(() {});
  }

  Future<void> _handleScrubPanEnd(DragEndDetails details) async {
    if (!_isHorizontalSeeking) {
      return;
    }

    final target = _clampDuration(
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
        Video(controller: _videoController, controls: NoVideoControls),
        if (_isBuffering && !_isHorizontalSeeking)
          const Center(child: CupertinoActivityIndicator(radius: 14)),
        if (_isHorizontalSeeking)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _formatDuration(
                  _clampDuration(
                    Duration(milliseconds: _dragSeekPreviewMs.round()),
                  ),
                ),
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
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.65),
                  Colors.black.withValues(alpha: 0.12),
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(28, 28),
                      onPressed: _toggleMuted,
                      child: Icon(
                        _isMuted
                            ? CupertinoIcons.speaker_slash_fill
                            : CupertinoIcons.speaker_2_fill,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(28, 28),
                      onPressed: () => _player.playOrPause().ignore(),
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
                        onChanged: _duration.inMilliseconds > 0
                            ? _seekTo
                            : null,
                        activeColor: Colors.white,
                        inactiveColor: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(_position),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _formatDuration(_duration),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_errorMessage != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withValues(alpha: 0.55)),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Per-page image viewer — display only, no action buttons.
// ---------------------------------------------------------------------------
class _ThreadMediaImagePage extends StatelessWidget {
  const _ThreadMediaImagePage({Key? key, required this.imageUrl})
    : super(key: key);

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 1,
      maxScale: 4,
      child: Center(
        child: Image.network(
          imageUrl,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
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
