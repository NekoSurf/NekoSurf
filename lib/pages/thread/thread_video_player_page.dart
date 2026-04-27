import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/save_videos.dart';
import 'package:flutter_chan/blocs/saved_attachments_model.dart';
import 'package:flutter_chan/services/cached_video.dart';
import 'package:flutter_chan/services/feed_player_pool.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

class ThreadVideoPlayerPage extends StatefulWidget {
  const ThreadVideoPlayerPage({
    Key? key,
    required this.videoUrl,
    this.title,
    this.board,
    this.fileName,
    this.startPosition = Duration.zero,
  }) : super(key: key);

  final String videoUrl;
  final String? title;
  final String? board;
  final String? fileName;
  final Duration startPosition;

  @override
  State<ThreadVideoPlayerPage> createState() => _ThreadVideoPlayerPageState();
}

class _ThreadVideoPlayerPageState extends State<ThreadVideoPlayerPage> {
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
  bool _showControls = true;
  Timer? _controlsHideTimer;
  double _dragSeekPreviewMs = 0;
  bool _isHorizontalSeeking = false;
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

    _player = Player();
    _videoController = VideoController(_player);

    _errorSub = _player.stream.error.listen((error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error;
      });
    });

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
      setState(() {
        _position = position;
      });
    });

    _durationSub = _player.stream.duration.listen((duration) {
      if (!mounted) {
        return;
      }
      setState(() {
        _duration = duration;
      });
    });

    _bufferingSub = _player.stream.buffering.listen((buffering) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isBuffering = buffering;
      });
    });

    _openAndPlay();
    // Pause any pool-managed feed players immediately so they don't hold the
    // AVAudioSession while the fullscreen player is starting up.
    FeedPlayerPool.instance.pauseAll();
    _startControlsAutoHide();
  }

  Future<void> _openAndPlay() async {
    try {
      final resolvedSource = await resolveCachedVideoSource(widget.videoUrl);
      if (!mounted) {
        return;
      }
      await _player.setPlaylistMode(PlaylistMode.loop);
      await _player.open(Media(resolvedSource), play: false);
      if (widget.startPosition > Duration.zero) {
        try {
          await _player.seek(widget.startPosition);
        } catch (_) {
          // Ignore seek races on open.
        }
      }
      if (!mounted) {
        return;
      }
      await _player.play();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
      });
    }
  }

  @override
  void dispose() {
    _controlsHideTimer?.cancel();
    _saveSuccessTimer?.cancel();
    _downloadSuccessTimer?.cancel();
    _errorSub?.cancel();
    _playingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferingSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _applyAudioMode() async {
    try {
      await _player.setVolume(_isMuted ? 0 : 100);
    } catch (_) {
      // Ignore transient volume races.
    }
  }

  Future<void> _toggleMuted() async {
    setState(() {
      _isMuted = !_isMuted;
    });
    await _applyAudioMode();
  }

  void _startControlsAutoHide() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || !_isPlaying) {
        return;
      }
      setState(() {
        _showControls = false;
      });
    });
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

  Future<void> _togglePlayPause() async {
    try {
      await _player.playOrPause();
    } catch (_) {
      // Ignore transient playback races.
    }
    setState(() {
      _showControls = true;
    });
    _startControlsAutoHide();
  }

  Future<void> _seekTo(double value) async {
    try {
      await _player.seek(_clampDuration(Duration(milliseconds: value.round())));
    } catch (_) {
      // Ignore transient seek races.
    }
    setState(() {
      _showControls = true;
    });
    _startControlsAutoHide();
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

  Future<void> _downloadToGallery() async {
    if (_isDownloading || widget.videoUrl.isEmpty || widget.fileName == null) {
      return;
    }
    setState(() {
      _isDownloading = true;
    });
    await saveVideo(widget.videoUrl, widget.fileName!, context, isSaved: false);
    if (!mounted) {
      return;
    }
    setState(() {
      _isDownloading = false;
      _didDownload = true;
      _showControls = true;
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
    if (_isSharing || widget.videoUrl.isEmpty || widget.fileName == null) {
      return;
    }
    setState(() {
      _isSharing = true;
    });
    await shareMedia(
      widget.videoUrl,
      widget.fileName!,
      context,
      isSaved: false,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isSharing = false;
      _showControls = true;
    });
  }

  Future<void> _saveToAttachments() async {
    if (_isSaving || widget.board == null || widget.fileName == null) {
      return;
    }

    final savedAttachments = context.read<SavedAttachmentsProvider>();
    final alreadySaved = savedAttachments.getSavedAttachments().any(
      (attachment) =>
          attachment.fileName?.split('/').last.split('.').first ==
          widget.fileName?.split('.').first,
    );

    if (alreadySaved) {
      _showSaveConfirmation();
      return;
    }

    setState(() {
      _isSaving = true;
    });

    await savedAttachments.addSavedAttachments(
      context,
      widget.board!,
      widget.fileName!,
    );

    if (!mounted) {
      return;
    }

    final saveSucceeded = savedAttachments.getSavedAttachments().any(
      (attachment) =>
          attachment.fileName?.split('/').last.split('.').first ==
          widget.fileName?.split('.').first,
    );

    setState(() {
      _isSaving = false;
      _showControls = true;
    });

    if (saveSucceeded) {
      _showSaveConfirmation();
    }
  }

  Future<void> _removeFromAttachments() async {
    if (_isRemoving || widget.board == null || widget.fileName == null) {
      return;
    }
    setState(() {
      _isRemoving = true;
    });
    await context.read<SavedAttachmentsProvider>().removeSavedAttachments(
      widget.fileName!,
      context,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isRemoving = false;
    });
  }

  void _showSaveConfirmation() {
    _saveSuccessTimer?.cancel();
    setState(() {
      _didSaveAttachment = true;
      _showControls = true;
    });
    _saveSuccessTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _didSaveAttachment = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _showControls = !_showControls;
          });
          if (_showControls) {
            _startControlsAutoHide();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Video(
                controller: _videoController,
                controls: NoVideoControls,
                fit: BoxFit.contain,
              ),
            ),
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
            if (_isBuffering && !_isHorizontalSeeking)
              const Center(child: CupertinoActivityIndicator(radius: 14)),
            if (_showControls)
              Positioned(
                top: topInset + 8,
                left: 8,
                child: CupertinoButton(
                  minimumSize: const Size(36, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(999),
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Icon(
                    CupertinoIcons.back,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            if (_showControls)
              Positioned(
                top: topInset + 10,
                right: 12,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.board != null && widget.fileName != null)
                      Builder(
                        builder: (context) {
                          final savedAttachments = context
                              .watch<SavedAttachmentsProvider>();
                          final isSaved = savedAttachments
                              .getSavedAttachments()
                              .any(
                                (a) =>
                                    a.fileName
                                        ?.split('/')
                                        .last
                                        .split('.')
                                        .first ==
                                    widget.fileName?.split('.').first,
                              );
                          if (isSaved) {
                            return CupertinoButton(
                              minimumSize: const Size(36, 36),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              color: Colors.black.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(999),
                              onPressed: _isRemoving
                                  ? null
                                  : _removeFromAttachments,
                              child: _isRemoving
                                  ? const CupertinoActivityIndicator(radius: 9)
                                  : const Icon(
                                      CupertinoIcons.trash,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                            );
                          }
                          return CupertinoButton(
                            minimumSize: const Size(36, 36),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            color: Colors.black.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(999),
                            onPressed: _isSaving || _didSaveAttachment
                                ? null
                                : _saveToAttachments,
                            child: _isSaving
                                ? const CupertinoActivityIndicator(radius: 9)
                                : Icon(
                                    _didSaveAttachment
                                        ? CupertinoIcons
                                              .check_mark_circled_solid
                                        : CupertinoIcons.add_circled,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                          );
                        },
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
                  ],
                ),
              ),
            if (_showControls)
              Positioned(
                left: 14,
                right: 14,
                bottom: 86,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.42),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
            if (_showControls)
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
                              inactiveColor: Colors.white.withValues(
                                alpha: 0.25,
                              ),
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
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.55),
                    ),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
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
          ],
        ),
      ),
    );
  }
}
