import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/save_videos.dart';
import 'package:flutter_chan/Models/saved_attachment.dart';
import 'package:flutter_chan/blocs/saved_attachments_model.dart';
import 'package:flutter_chan/pages/media/shared_media_viewer.dart';
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
    _currentIndex = widget.initialIndex;
    _attachments = List<SavedAttachment>.from(widget.attachments);
  }

  @override
  void dispose() {
    _downloadSuccessTimer?.cancel();
    super.dispose();
  }

  String _fileName(SavedAttachment attachment) {
    return attachment.fileName?.split('/').last ?? '';
  }

  String _filePath(SavedAttachment attachment) {
    final fileName = _fileName(attachment);
    return '${widget.directoryPath}/savedAttachments/$fileName';
  }

  List<SharedMediaViewerItem> get _items {
    return _attachments
        .map((SavedAttachment attachment) {
          final bool isVideo =
              attachment.savedAttachmentType == SavedAttachmentType.Video;
          final String path = _filePath(attachment);

          return SharedMediaViewerItem(
            id: path,
            source: path,
            isVideo: isVideo,
            imageProvider: FileImage(File(path)),
            resolveVideoSource: (String source) async {
              return Uri.file(source).toString();
            },
            thumbnail: FileImage(
              File(
                '${widget.directoryPath}/savedAttachments/${attachment.thumbnail}',
              ),
            ),
          );
        })
        .toList(growable: false);
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
  }

  @override
  Widget build(BuildContext context) {
    return SharedMediaViewer(
      items: _items,
      initialIndex: _currentIndex,
      onClose: () => Navigator.of(context).maybePop(),
      onIndexChanged: (int index) {
        setState(() {
          _currentIndex = index;
        });
      },

      actions: SharedMediaViewerTopBarActions(
        saveToggle: SharedMediaViewerSaveToggleAction(
          isSaved: true,
          isSaving: false,
          isRemoving: _isRemoving,
          didSave: true,
          onRemove: _removeCurrentAttachment,
          onSave: () {},
        ),
        download: SharedMediaViewerDownloadAction(
          isDownloading: _isDownloading,
          didDownload: _didDownload,
          onDownload: _downloadCurrentToGallery,
        ),
        share: SharedMediaViewerShareAction(
          isSharing: _isSharing,
          onShare: _shareCurrentMedia,
        ),
      ),
    );
  }
}
