import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/save_videos.dart';
import 'package:flutter_chan/Models/saved_attachment.dart';
import 'package:flutter_chan/blocs/saved_attachments_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/pages/savedAttachments/permission_denied.dart';
import 'package:flutter_chan/pages/savedAttachments/saved_media_viewer_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SavedAttachments extends ConsumerStatefulWidget {
  const SavedAttachments({Key? key}) : super(key: key);

  @override
  ConsumerState<SavedAttachments> createState() => _SavedAttachmentsState();
}

class _SavedAttachmentsState extends ConsumerState<SavedAttachments> {
  final ScrollController scrollController = ScrollController();

  // Placeholder; set to the real app directory in _loadAttachments().
  Directory directory = Directory('');

  bool _isLoading = true;
  bool _hasPermissionError = false;

  String _attachmentThumbnailPath(SavedAttachment attachment) {
    return '${directory.path}/savedAttachments/${attachment.thumbnail}';
  }

  Future<void> _openSavedMediaViewer(
    List<SavedAttachment> attachments,
    int initialIndex,
  ) async {
    if (attachments.isEmpty) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SavedMediaViewerPage(
          attachments: attachments,
          initialIndex: initialIndex,
          directoryPath: directory.path,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    // Ensure this page rebuilds immediately after returning from viewer edits.
    setState(() {});
  }

  Widget _buildAttachmentTile(
    SavedAttachment attachment,
    List<SavedAttachment> attachments,
    int index,
  ) {
    final bool isVideo =
        attachment.savedAttachmentType == SavedAttachmentType.Video;

    final tile = Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          fit: BoxFit.cover,
          image: FileImage(File(_attachmentThumbnailPath(attachment))),
        ),
      ),
      child: isVideo
          ? Center(
              child: Icon(
                CupertinoIcons.play,
                color: Colors.white,
                size: 50,
                shadows: [
                  Shadow(
                    blurRadius: 10,
                    color: Colors.black.withValues(alpha: 0.6),
                  ),
                ],
              ),
            )
          : Container(),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openSavedMediaViewer(attachments, index),
      child: tile,
    );
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_isLoading) {
      _loadAttachments();
    }
  }

  Future<void> _loadAttachments() async {
    try {
      directory = await requestDirectory(
        directory,
        context,
        showErrorDialog: false,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _hasPermissionError = true;
        _isLoading = false;
      });
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final savedAttachments = ref.watch(savedAttachmentsProvider);
    final bool isDark = theme == ThemeData.dark();
    final List<SavedAttachment> attachments = savedAttachments
        .getSavedAttachments();
    final bool isEmpty =
        !_isLoading && !_hasPermissionError && attachments.isEmpty;

    if (_isLoading)
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: SizedBox.shrink(),
      );
    else if (_hasPermissionError) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: PermissionDenied(),
      );
    } else if (isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Column(
          children: [
            const SizedBox(height: 30),
            Text(
              'Save Attachments first!',
              style: TextStyle(
                fontSize: 26,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
      );
    } else {
      return SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) =>
              _buildAttachmentTile(attachments[index], attachments, index),
          childCount: attachments.length,
        ),
      );
    }
  }
}
