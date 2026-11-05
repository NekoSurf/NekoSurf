import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/API/save_videos.dart';
import 'package:flutter_chan/Models/saved_attachment.dart';
import 'package:flutter_chan/blocs/saved_attachments_model.dart';
import 'package:flutter_chan/pages/media/shared_media_viewer.dart';
import 'package:flutter_chan/services/show_snackbar.dart';
import 'package:flutter_chan/widgets/dash_dialogs.dart';
import 'package:provider/provider.dart';

class SavedMediaViewerPage extends StatefulWidget {
  const SavedMediaViewerPage({
    super.key,
    required this.attachments,
    required this.initialIndex,
    required this.directoryPath,
  });

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

  // Each file goes to Photos on its own (by file name), so several can at
  // once; its check mark shows while its timer runs.
  final Set<String> _downloading = <String>{};
  final Map<String, Timer> _downloadedChecks = <String, Timer>{};

  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _attachments = List<SavedAttachment>.from(widget.attachments);
  }

  @override
  void dispose() {
    for (final Timer timer in _downloadedChecks.values) {
      timer.cancel();
    }
    super.dispose();
  }

  String _fileName(SavedAttachment attachment) {
    return attachment.fileName?.split('/').last ?? '';
  }

  String _displayName(SavedAttachment attachment) {
    return attachment.originalName ?? _fileName(attachment);
  }

  String _filePath(SavedAttachment attachment) {
    final fileName = _fileName(attachment);
    return savedMediaPath(widget.directoryPath, fileName);
  }

  List<SharedMediaViewerItem> get _items {
    return _attachments
        .map((SavedAttachment attachment) {
          final bool isVideo =
              attachment.savedAttachmentType == SavedAttachmentType.video;
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
              File(savedThumbnailPath(widget.directoryPath, attachment)),
            ),
          );
        })
        .toList(growable: false);
  }

  Future<void> _downloadCurrentToGallery() async {
    if (_attachments.isEmpty) {
      return;
    }
    final String fileName = _fileName(_attachments[_currentIndex]);
    if (!_downloading.add(fileName)) {
      return;
    }
    setState(() {});
    final int? failed = await saveSavedAttachmentsToGallery(<String>[
      fileName,
    ], context);
    if (!mounted) {
      return;
    }
    if ((failed ?? 0) > 0) {
      showCupertinoSnackbar(
        const Duration(milliseconds: 1800),
        true,
        context,
        "Couldn't save it to Photos",
      );
    }
    setState(() {
      _downloading.remove(fileName);
      if (failed == 0) {
        _downloadedChecks[fileName]?.cancel();
        _downloadedChecks[fileName] = Timer(
          const Duration(milliseconds: 1200),
          () {
            if (mounted) {
              setState(() {
                _downloadedChecks.remove(fileName);
              });
            }
          },
        );
      }
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
    await shareSavedAttachments(<String>[fileName], context);
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

    final provider = context.read<SavedAttachmentsProvider>();
    final attachment = _attachments[_currentIndex];
    final id = provider.attachmentId(attachment);

    final bool? confirmed = await showDashDialog<bool>(
      context: context,
      builder: (dialogContext) => DashDialog(
        title: const Text('Delete attachment?'),
        content: const Text('This removes it from your saved attachments.'),
        actions: [
          DashDialogAction(
            isDefaultAction: true,
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          DashDialogAction(
            isDestructiveAction: true,
            child: const Text('Delete'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isRemoving = true;
    });

    await provider.removeSavedAttachments(id, context);

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
    final String currentFileName = _attachments.isEmpty
        ? ''
        : _fileName(_attachments[_currentIndex]);
    return SharedMediaViewer(
      items: _items,
      initialIndex: _currentIndex,
      mediaNameBuilder: (int index) => _displayName(_attachments[index]),
      onClose: () => Navigator.of(context).maybePop(),
      onIndexChanged: (int index) {
        setState(() {
          _currentIndex = index;
        });
      },

      actions: [
        SharedMediaViewerAction(
          icon: CupertinoIcons.trash,
          label: 'Delete',
          onPressed: (_) => _removeCurrentAttachment(),
          isBusy: _isRemoving,
        ),
        SharedMediaViewerAction(
          icon: CupertinoIcons.arrow_down_to_line,
          label: 'Save to Photos',
          onPressed: (_) => _downloadCurrentToGallery(),
          isBusy: _downloading.contains(currentFileName),
          isCompleted: _downloadedChecks.containsKey(currentFileName),
        ),
        SharedMediaViewerAction(
          icon: CupertinoIcons.share,
          label: 'Share',
          onPressed: (_) => _shareCurrentMedia(),
          isBusy: _isSharing,
        ),
      ],
    );
  }
}
