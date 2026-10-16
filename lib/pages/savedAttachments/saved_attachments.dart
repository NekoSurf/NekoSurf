import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chan/API/save_videos.dart';
import 'package:flutter_chan/Models/saved_attachment.dart';
import 'package:flutter_chan/blocs/saved_attachments_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/pages/savedAttachments/permission_denied.dart';
import 'package:flutter_chan/pages/savedAttachments/saved_media_viewer_page.dart';
import 'package:provider/provider.dart';

class SavedAttachments extends StatefulWidget {
  const SavedAttachments({Key? key}) : super(key: key);

  @override
  State<SavedAttachments> createState() => _SavedAttachmentsState();
}

class _SavedAttachmentsState extends State<SavedAttachments>
    with WidgetsBindingObserver {
  final ScrollController scrollController = ScrollController();

  // Placeholder; set to the real app directory in _loadAttachments().
  Directory directory = Directory('');

  bool _isLoading = true;
  bool _hasPermissionError = false;

  String _key(SavedAttachment a) => a.fileName?.split('/').last ?? '';

  String _attachmentThumbnailPath(SavedAttachment attachment) {
    return savedThumbnailPath(directory.path, attachment);
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
    final bool isGif = (attachment.fileName ?? '').toLowerCase().endsWith(
      '.gif',
    );

    final tile = Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          File(_attachmentThumbnailPath(attachment)),
          fit: BoxFit.cover,
          cacheWidth: 400,
          errorBuilder: (_, __, ___) => Container(
            color: CupertinoColors.systemGrey5.resolveFrom(context),
            child: const Icon(
              CupertinoIcons.photo,
              color: CupertinoColors.systemGrey,
            ),
          ),
        ),
        if (isVideo)
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isGif)
                    const Icon(
                      CupertinoIcons.play_fill,
                      color: Colors.white,
                      size: 11,
                    ),
                  if (isGif)
                    const Text(
                      'GIF',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );

    final provider = Provider.of<SavedAttachmentsProvider>(context);
    final bool selecting = provider.selecting;
    final String key = _key(attachment);
    final bool isSelected = provider.selected.contains(key);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!selecting) {
          _openSavedMediaViewer(attachments, index);
          return;
        }
        provider.toggleSelected(key);
      },
      onLongPress: () {
        if (selecting) {
          return;
        }
        HapticFeedback.selectionClick();
        provider.setSelecting(true);
        provider.toggleSelected(key);
      },
      child: AnimatedScale(
        scale: isSelected ? 0.88 : 1,
        duration: const Duration(milliseconds: 120),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(isSelected ? 8 : 0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              tile,
              if (selecting)
                Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? CupertinoColors.activeBlue
                            : Colors.black.withValues(alpha: 0.25),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: isSelected
                          ? const Icon(
                              CupertinoIcons.check_mark,
                              color: Colors.white,
                              size: 13,
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Files may have been deleted in the Files app while backgrounded.
    if (state == AppLifecycleState.resumed && !_isLoading) {
      _reconcile();
    }
  }

  Future<void> _reconcile() async {
    final provider = Provider.of<SavedAttachmentsProvider>(
      context,
      listen: false,
    );
    await provider.reconcileWithDisk(directory.path);
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

    await _reconcile();

    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeChanger>(context);
    final savedAttachments = Provider.of<SavedAttachmentsProvider>(context);
    final bool isDark = theme.getTheme() == ThemeData.dark();
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
            const SizedBox(height: 60),
            Icon(
              CupertinoIcons.paperclip,
              size: 56,
              color: CupertinoColors.systemGrey.resolveFrom(context),
            ),
            const SizedBox(height: 12),
            Text(
              'No Saved Attachments',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Open an image or video in a thread and save it to keep it here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: CupertinoColors.systemGrey),
              ),
            ),
          ],
        ),
      );
    } else {
      return SliverMainAxisGroup(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildAttachmentTile(
                  attachments[index],
                  attachments,
                  index,
                ),
                childCount: attachments.length,
              ),
            ),
          ),
        ],
      );
    }
  }
}
