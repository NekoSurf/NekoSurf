import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/media/shared_media_viewer.dart';
import 'package:flutter_chan/saved/give_media.dart';
import 'package:flutter_chan/saved/media_tasks.dart';
import 'package:flutter_chan/saved/report_failure.dart';
import 'package:flutter_chan/saved/saved_attachment.dart';
import 'package:flutter_chan/saved/saved_attachments_model.dart';
import 'package:flutter_chan/saved/saved_folders.dart';
import 'package:flutter_chan/ui/dash_dialogs.dart';
import 'package:provider/provider.dart';

class SavedMediaViewerPage extends StatefulWidget {
  const SavedMediaViewerPage({
    super.key,
    required this.attachments,
    required this.initialIndex,
    required this.folders,
  });

  final List<SavedAttachment> attachments;
  final int initialIndex;
  final SavedFolders folders;

  @override
  State<SavedMediaViewerPage> createState() => _SavedMediaViewerPageState();
}

class _SavedMediaViewerPageState extends State<SavedMediaViewerPage> {
  late int _currentIndex = widget.initialIndex;
  late final List<SavedAttachment> _attachments = List.of(widget.attachments);

  // By file name, as each file is on its own.
  final MediaTasks _removals = MediaTasks();
  final MediaTasks _toPhotos = MediaTasks();
  final MediaTasks _shares = MediaTasks();

  @override
  void initState() {
    super.initState();
    for (final MediaTasks tasks in [_removals, _toPhotos, _shares]) {
      tasks.addListener(_rebuild);
    }
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _removals.dispose();
    _toPhotos.dispose();
    _shares.dispose();
    super.dispose();
  }

  SavedAttachment get _current => _attachments[_currentIndex];

  List<SharedMediaViewerItem> get _items {
    return _attachments
        .map((SavedAttachment attachment) {
          final String path = widget.folders.mediaPath(attachment);

          return SharedMediaViewerItem(
            id: path,
            name: attachment.fileName,
            source: path,
            isVideo: attachment.isVideo,
            imageProvider: FileImage(File(path)),
            thumbnail: FileImage(
              File(widget.folders.thumbnailPath(attachment)),
            ),
          );
        })
        .toList(growable: false);
  }

  Future<void> _saveToPhotos() async {
    final String fileName = _current.fileName;
    await reportingFailure(
      context,
      () => _toPhotos.run(fileName, (_) async {
        if (await copySavedToPhotos(<String>[fileName]) > 0) {
          throw Exception('gallery save failed');
        }
      }),
      message: "Couldn't save it to Photos",
    );
  }

  Future<void> _share() async {
    final String fileName = _current.fileName;
    await reportingFailure(
      context,
      () => _shares.run(fileName, (_) => shareSaved(<String>[fileName])),
      message: "Couldn't share it",
    );
  }

  Future<void> _remove() async {
    final SavedAttachmentsProvider provider = context
        .read<SavedAttachmentsProvider>();
    final SavedAttachment attachment = _current;

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

    final bool removed = await reportingFailure(
      context,
      () => _removals.run(
        attachment.fileName,
        (_) => provider.remove(attachment.id),
      ),
      message: "Couldn't delete it",
    );
    if (!removed || !mounted) {
      return;
    }

    if (_attachments.length == 1) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _attachments.remove(attachment);
      if (_currentIndex >= _attachments.length) {
        _currentIndex = _attachments.length - 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final String fileName = _current.fileName;
    return SharedMediaViewer(
      items: _items,
      index: _currentIndex,
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
          onPressed: (_) => _remove(),
          isBusy: _removals.isRunning(fileName),
        ),
        SharedMediaViewerAction(
          icon: CupertinoIcons.arrow_down_to_line,
          label: 'Save to Photos',
          onPressed: (_) => _saveToPhotos(),
          isBusy: _toPhotos.isRunning(fileName),
          isCompleted: _toPhotos.isDone(fileName),
        ),
        SharedMediaViewerAction(
          icon: CupertinoIcons.share,
          label: 'Share',
          onPressed: (_) => _share(),
          isBusy: _shares.isRunning(fileName),
        ),
      ],
    );
  }
}
