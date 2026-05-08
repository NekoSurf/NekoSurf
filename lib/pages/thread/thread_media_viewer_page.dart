import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/save_videos.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/saved_attachments_model.dart';
import 'package:flutter_chan/pages/media/shared_media_viewer.dart';
import 'package:flutter_chan/services/cached_video.dart';
import 'package:provider/provider.dart';

class ThreadMediaViewerRoute extends MaterialPageRoute<int> {
  ThreadMediaViewerRoute({
    required List<Post> mediaPosts,
    required int initialIndex,
    required String board,
    required int thread,
  }) : this._(
         mediaPosts: mediaPosts,
         initialIndex: initialIndex,
         board: board,
         thread: thread,
         currentPostId: ValueNotifier<int?>(
           _resolveInitialPostId(mediaPosts, initialIndex),
         ),
       );

  ThreadMediaViewerRoute._({
    required List<Post> mediaPosts,
    required int initialIndex,
    required String board,
    required int thread,
    required ValueNotifier<int?> currentPostId,
  }) : _currentPostId = currentPostId,
       super(
         builder: (BuildContext context) => ThreadMediaViewerPage(
           mediaPosts: mediaPosts,
           initialIndex: initialIndex,
           board: board,
           thread: thread,
           currentPostIdNotifier: currentPostId,
         ),
       );

  final ValueNotifier<int?> _currentPostId;

  @override
  int? get currentResult => _currentPostId.value;

  @override
  void dispose() {
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
    Key? key,
    required this.mediaPosts,
    required this.initialIndex,
    required this.board,
    required this.thread,
    required this.currentPostIdNotifier,
  }) : super(key: key);

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
    widget.currentPostIdNotifier.value = _currentPostId;
  }

  @override
  void dispose() {
    _saveSuccessTimer?.cancel();
    _downloadSuccessTimer?.cancel();
    super.dispose();
  }

  Post get _currentPost => widget.mediaPosts[_currentIndex];

  int? get _currentPostId => _currentPost.no ?? _currentPost.tim;

  bool _isVideo(Post post) => post.ext == '.webm' || post.ext == '.mp4';

  String _mediaUrl(Post post) =>
      'https://i.4cdn.org/${widget.board}/${post.tim}${post.ext}';

  String _fileName(Post post) => '${post.tim}${post.ext}';

  List<SharedMediaViewerItem> get _items {
    return widget.mediaPosts
        .map((Post post) {
          final String mediaUrl = _mediaUrl(post);

          return SharedMediaViewerItem(
            id: '${post.no ?? post.tim}',
            source: mediaUrl,
            isVideo: _isVideo(post),
            imageProvider: NetworkImage(mediaUrl),
            resolveVideoSource: resolveCachedVideoSource,
            thumbnail: NetworkImage(
              'https://i.4cdn.org/${widget.board}/${post.tim}s.jpg',
            ),
          );
        })
        .toList(growable: false);
  }

  Future<void> _saveToAttachments() async {
    if (_isSaving) {
      return;
    }
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
    if (!mounted) {
      return;
    }
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
    if (_isRemoving) {
      return;
    }
    setState(() {
      _isRemoving = true;
    });
    await context.read<SavedAttachmentsProvider>().removeSavedAttachments(
      _fileName(_currentPost),
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

  Future<void> _downloadToGallery() async {
    if (_isDownloading) {
      return;
    }
    final post = _currentPost;
    setState(() {
      _isDownloading = true;
    });
    await saveVideo(_mediaUrl(post), _fileName(post), context, isSaved: false);
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

  void _closeWithCurrentPost() {
    Navigator.of(context).pop(_currentPostId);
  }

  @override
  Widget build(BuildContext context) {
    final savedAttachments = context.watch<SavedAttachmentsProvider>();
    final fileName = _fileName(_currentPost);
    final isSaved = savedAttachments.getSavedAttachments().any(
      (a) =>
          a.fileName?.split('/').last.split('.').first ==
          fileName.split('.').first,
    );

    return SharedMediaViewer(
      items: _items,
      initialIndex: _currentIndex,
      onClose: _closeWithCurrentPost,
      onIndexChanged: (int index) {
        if (index == _currentIndex) {
          return;
        }
        setState(() {
          _didSaveAttachment = false;
          _didDownload = false;
          _currentIndex = index;
        });
        widget.currentPostIdNotifier.value = _currentPostId;
      },
      actions: SharedMediaViewerTopBarActions(
        saveToggle: SharedMediaViewerSaveToggleAction(
          isSaved: isSaved,
          isSaving: _isSaving,
          isRemoving: _isRemoving,
          didSave: _didSaveAttachment,
          onSave: _saveToAttachments,
          onRemove: _removeFromAttachments,
        ),
        download: SharedMediaViewerDownloadAction(
          isDownloading: _isDownloading,
          didDownload: _didDownload,
          onDownload: _downloadToGallery,
        ),
        share: SharedMediaViewerShareAction(
          isSharing: _isSharing,
          onShare: _shareCurrentMedia,
        ),
      ),
    );
  }
}
