import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/save_videos.dart';
import 'package:flutter_chan/Models/saved_attachment.dart';
import 'package:flutter_chan/blocs/saved_attachments_model.dart';
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

  @override
  void initState() {
    super.initState();
    _attachments = List<SavedAttachment>.from(widget.attachments);
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _downloadSuccessTimer?.cancel();
    _pageController.dispose();
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

    if (isVideo) {
      return SavedMediaVideoPage(
        key: ValueKey('saved-video-$index-${_fileName(attachment)}'),
        filePath: _filePath(attachment),
        isActive: _currentIndex == index,
      );
    }

    return InteractiveViewer(
      minScale: 1,
      maxScale: 4,
      child: Center(
        child: Image.file(
          File(_filePath(attachment)),
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
    final bottomInset = MediaQuery.of(context).padding.bottom;

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
                CupertinoButton(
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                    CupertinoButton(
                      minimumSize: const Size(36, 36),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(999),
                      onPressed: _isRemoving ? null : _removeCurrentAttachment,
                      child: _isRemoving
                          ? const CupertinoActivityIndicator(radius: 9)
                          : const Icon(
                              CupertinoIcons.delete,
                              color: Colors.white,
                              size: 18,
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                height: 96 + bottomInset,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.0),
                      Colors.black.withValues(alpha: 0.38),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: bottomInset + 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_currentIndex + 1} / ${_attachments.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

class SavedMediaVideoPage extends StatefulWidget {
  const SavedMediaVideoPage({
    Key? key,
    required this.filePath,
    required this.isActive,
  }) : super(key: key);

  final String filePath;
  final bool isActive;

  @override
  State<SavedMediaVideoPage> createState() => _SavedMediaVideoPageState();
}

class _SavedMediaVideoPageState extends State<SavedMediaVideoPage> {
  static const double _backSwipeEdgeInset = 24;

  late final Player _player;
  late final VideoController _videoController;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  double _dragSeekPreviewMs = 0;
  bool _isHorizontalSeeking = false;

  @override
  void initState() {
    super.initState();

    _player = Player();
    _videoController = VideoController(_player);

    _positionSub = _player.stream.position.listen((value) {
      if (!mounted) {
        return;
      }
      setState(() {
        _position = value;
      });
    });

    _durationSub = _player.stream.duration.listen((value) {
      if (!mounted) {
        return;
      }
      setState(() {
        _duration = value;
      });
    });

    _playingSub = _player.stream.playing.listen((value) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPlaying = value;
      });
    });

    _open();
  }

  Future<void> _open() async {
    final media = Media(Uri.file(widget.filePath).toString());
    await _player.setPlaylistMode(PlaylistMode.loop);
    await _player.open(media, play: widget.isActive);
  }

  @override
  void didUpdateWidget(covariant SavedMediaVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.filePath != widget.filePath) {
      _open();
      return;
    }

    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        _player.play();
      } else {
        _player.pause();
      }
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _player.dispose();
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
    await _player.playOrPause();
  }

  Future<void> _seekTo(double value) async {
    await _player.seek(_clampDuration(Duration(milliseconds: value.round())));
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
            controller: _videoController,
            controls: NoVideoControls,
            fit: BoxFit.contain,
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
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                12,
                8,
                12,
                56 + MediaQuery.of(context).padding.bottom,
              ),
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
    );
  }
}
