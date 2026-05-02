import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/save_videos.dart';
import 'package:flutter_chan/Models/saved_attachment.dart';
import 'package:flutter_chan/blocs/saved_attachments_model.dart';
import 'package:flutter_chan/utils/build_blur_pill.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

class SavedMediaViewerPage extends StatefulWidget {
  const SavedMediaViewerPage({
    Key? key,
    required this.attachments,
    required this.initialIndex,
    required this.directoryPath,
  }) : super(key: key);

  final List<SavedAttachment> attachments;
  final int initialIndex;
  final String directoryPath;

  @override
  State<SavedMediaViewerPage> createState() => _SavedMediaViewerPageState();
}

class _SavedMediaViewerPageState extends State<SavedMediaViewerPage> {
  late final PageController _pageController;
  late int _currentIndex;
  late List<SavedAttachment> _attachments;
  bool _isRemoving = false;
  bool _isDownloading = false;
  bool _didDownload = false;
  Timer? _downloadSuccessTimer;
  bool _isSharing = false;

  // A single long-lived Player + VideoController shared across all video pages,
  // matching the pattern used in ThreadMediaViewerPage to avoid the ~1 s
  // AVAudioSession reconfiguration pause on iOS (media-kit #964).
  late final Player _viewerPlayer;
  late final VideoController _viewerController;

  // Persists each video's playback position (keyed by file path) so that
  // scrolling back to a video resumes where the user left off.
  final Map<String, Duration> _savedPositions = {};

  @override
  void initState() {
    super.initState();
    _attachments = List<SavedAttachment>.from(widget.attachments);
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);

    _viewerPlayer = Player();
    _viewerController = VideoController(_viewerPlayer);
    _viewerPlayer.setPlaylistMode(PlaylistMode.loop).ignore();
  }

  @override
  void dispose() {
    _downloadSuccessTimer?.cancel();
    _pageController.dispose();
    _viewerPlayer.dispose();
    super.dispose();
  }

  String _fileName(SavedAttachment attachment) {
    return attachment.fileName?.split('/').last ?? '';
  }

  String _filePath(SavedAttachment attachment) {
    final fileName = _fileName(attachment);
    return '${widget.directoryPath}/savedAttachments/$fileName';
  }

  Widget _buildMediaPage(SavedAttachment attachment, int index) {
    final isVideo = attachment.savedAttachmentType == SavedAttachmentType.Video;
    final path = _filePath(attachment);

    if (isVideo) {
      return SavedMediaVideoPage(
        key: ValueKey('saved-video-$index-$path'),
        filePath: path,
        player: _viewerPlayer,
        controller: _viewerController,
        isActive: _currentIndex == index,
        startPosition: _savedPositions[path] ?? Duration.zero,
        onPositionSave: (pos) {
          _savedPositions[path] = pos;
        },
      );
    }

    return InteractiveViewer(
      minScale: 1,
      maxScale: 4,
      child: Center(
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
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

  Future<void> _downloadCurrentToGallery() async {
    if (_isDownloading || _attachments.isEmpty) {
      return;
    }
    final attachment = _attachments[_currentIndex];
    final fileName = _fileName(attachment);
    setState(() {
      _isDownloading = true;
    });
    await saveVideo(fileName, fileName, context, isSaved: true);
    if (!mounted) {
      return;
    }
    setState(() {
      _isDownloading = false;
      _didDownload = true;
    });
    _downloadSuccessTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _didDownload = false;
      });
    });
  }

  Future<void> _shareCurrentMedia() async {
    if (_isSharing || _attachments.isEmpty) {
      return;
    }
    final attachment = _attachments[_currentIndex];
    final fileName = _fileName(attachment);
    setState(() {
      _isSharing = true;
    });
    await shareMedia(fileName, fileName, context, isSaved: true);
    if (!mounted) {
      return;
    }
    setState(() {
      _isSharing = false;
    });
  }

  Future<void> _removeCurrentAttachment() async {
    if (_isRemoving || _attachments.isEmpty) {
      return;
    }

    final attachment = _attachments[_currentIndex];
    final fileName = _fileName(attachment);

    setState(() {
      _isRemoving = true;
    });

    await context.read<SavedAttachmentsProvider>().removeSavedAttachments(
      fileName,
      context,
    );

    if (!mounted) {
      return;
    }

    final nextAttachments = List<SavedAttachment>.from(_attachments)
      ..removeAt(_currentIndex);

    if (nextAttachments.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }

    final nextIndex = _currentIndex >= nextAttachments.length
        ? nextAttachments.length - 1
        : _currentIndex;

    setState(() {
      _attachments = nextAttachments;
      _currentIndex = nextIndex;
      _isRemoving = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) {
        return;
      }
      _pageController.jumpToPage(nextIndex);
    });
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: _attachments.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return _buildMediaPage(_attachments[index], index);
            },
          ),
          Positioned(
            top: topInset + 8,
            left: 8,
            right: 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                buildBlurPill(
                  child: CupertinoButton(
                    minimumSize: const Size(36, 36),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Icon(
                      CupertinoIcons.back,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    buildBlurPill(
                      child: CupertinoButton(
                        minimumSize: const Size(36, 36),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                        onPressed: _isDownloading || _didDownload
                            ? null
                            : _downloadCurrentToGallery,
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
                    ),
                    const SizedBox(width: 8),
                    buildBlurPill(
                      child: CupertinoButton(
                        minimumSize: const Size(36, 36),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        color: Colors.transparent,
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
                    ),
                    const SizedBox(width: 8),
                    buildBlurPill(
                      child: CupertinoButton(
                        minimumSize: const Size(36, 36),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                        onPressed: _isRemoving
                            ? null
                            : _removeCurrentAttachment,
                        child: _isRemoving
                            ? const CupertinoActivityIndicator(radius: 9)
                            : const Icon(
                                CupertinoIcons.delete,
                                color: Colors.white,
                                size: 18,
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    buildBlurPill(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        '${_currentIndex + 1} / ${_attachments.length}',
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
    );
  }
}

class SavedMediaVideoPage extends StatefulWidget {
  const SavedMediaVideoPage({
    Key? key,
    required this.filePath,
    required this.player,
    required this.controller,
    required this.isActive,
    required this.onPositionSave,
    this.startPosition = Duration.zero,
  }) : super(key: key);

  final String filePath;
  final Player player;
  final VideoController controller;
  final bool isActive;
  final ValueChanged<Duration> onPositionSave;
  final Duration startPosition;

  @override
  State<SavedMediaVideoPage> createState() => _SavedMediaVideoPageState();
}

class _SavedMediaVideoPageState extends State<SavedMediaVideoPage> {
  static const double _backSwipeEdgeInset = 24;

  // Stream subscriptions — attached only while this page is active.
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _bufferingSub;

  // True from the moment a page becomes active until the first playing=true
  // event fires for the new media.  The black overlay shown during this window
  // hides the last decoded frame of the previous video.
  bool _isTransitioning = true;
  bool _isPlaying = false;
  bool _isBuffering = false;
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

  void _attachSubscriptions() {
    _cancelSubscriptions();
    _playingSub = widget.player.stream.playing.listen((playing) {
      if (!mounted) return;
      setState(() {
        _isPlaying = playing;
        if (playing) _isTransitioning = false;
      });
    });
    _positionSub = widget.player.stream.position.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });
    _durationSub = widget.player.stream.duration.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d);
    });
    _bufferingSub = widget.player.stream.buffering.listen((b) {
      if (!mounted) return;
      setState(() => _isBuffering = b);
    });
  }

  void _cancelSubscriptions() {
    _playingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferingSub?.cancel();
    _playingSub = null;
    _positionSub = null;
    _durationSub = null;
    _bufferingSub = null;
  }

  void _resetPlaybackState() {
    setState(() {
      _isPlaying = false;
      _isBuffering = false;
      _isTransitioning = true;
      _position = Duration.zero;
      _duration = Duration.zero;
      _isHorizontalSeeking = false;
    });
  }

  /// Mirrors the feed-player fix for media-kit #964: on iOS, explicitly
  /// selecting AudioTrack.auto() before play() prevents the player from doing a
  /// lazy AVAudioSession reconfiguration ~1 second into playback.
  Future<void> _applyAudioMode() async {
    try {
      if (Platform.isIOS) {
        await widget.player.setAudioTrack(AudioTrack.auto());
      }
    } catch (_) {
      // Ignore transient audio track races.
    }
  }

  Future<void> _openAndPlay() async {
    final snapshotPath = widget.filePath;
    try {
      await widget.player.open(
        Media(Uri.file(snapshotPath).toString()),
        play: false,
      );
      if (!mounted || !widget.isActive || widget.filePath != snapshotPath) {
        return;
      }
      if (widget.startPosition > Duration.zero) {
        try {
          await widget.player.seek(widget.startPosition);
        } catch (_) {
          // Ignore seek races on open.
        }
      }
      if (!mounted || !widget.isActive) return;
      await _applyAudioMode();
      await widget.player.play();
    } catch (_) {
      // Playback errors are not surfaced in the saved viewer.
    }
  }

  @override
  void didUpdateWidget(covariant SavedMediaVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.filePath != widget.filePath) {
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
      widget.onPositionSave(_position);
      widget.player.pause().ignore();
      _cancelSubscriptions();
      _resetPlaybackState();
    }
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    // Do NOT dispose the player — it is owned by _SavedMediaViewerPageState.
    super.dispose();
  }

  String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
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

  Future<void> _togglePlayPause() async {
    await widget.player.playOrPause();
  }

  Future<void> _seekTo(double value) async {
    await widget.player.seek(
      _clampDuration(Duration(milliseconds: value.round())),
    );
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
  }

  void _handleScrubPanUpdate(DragUpdateDetails details) {
    if (!_isHorizontalSeeking) {
      return;
    }
    final width = MediaQuery.of(context).size.width - _backSwipeEdgeInset;
    if (width <= 0) {
      return;
    }

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
    await _seekTo(target.inMilliseconds.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Video(
            controller: widget.controller,
            controls: NoVideoControls,
            fit: BoxFit.contain,
          ),
          // Black overlay hides the last decoded frame of the previous video
          // while the new media is opening.  Cleared once playing=true fires.
          if (_isTransitioning) const ColoredBox(color: Colors.black),
          if ((_isBuffering || _isTransitioning) && !_isHorizontalSeeking)
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.14),
                        width: 0.5,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
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
                            onChanged: _duration.inMilliseconds > 0
                                ? _seekTo
                                : null,
                            activeColor: Colors.white,
                            inactiveColor: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                        Text(
                          '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
