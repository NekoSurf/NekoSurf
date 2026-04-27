import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/save_videos.dart';
import 'package:flutter_chan/Models/saved_attachment.dart';
import 'package:flutter_chan/blocs/saved_attachments_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/constants.dart';
import 'package:flutter_chan/pages/savedAttachments/permission_denied.dart';
import 'package:flutter_chan/pages/savedAttachments/saved_media_viewer_page.dart';
import 'package:provider/provider.dart';

class SavedAttachments extends StatefulWidget {
  const SavedAttachments({Key? key}) : super(key: key);

  @override
  State<SavedAttachments> createState() => _SavedAttachmentsState();
}

class _SavedAttachmentsState extends State<SavedAttachments> {
  final ScrollController scrollController = ScrollController();

  // Placeholder; set to the real app directory in _loadAttachments().
  Directory directory = Directory('');

  List<SavedAttachment>? _loadedAttachments;
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

    convertLegacySavedAttachments();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_isLoading) {
      _loadAttachments();
    }
  }

  void convertLegacySavedAttachments() {
    if (Platform.isIOS) {
      final savedAttachments = Provider.of<SavedAttachmentsProvider>(
        context,
        listen: false,
      );
      final List<SavedAttachment> savedAttachmentList = savedAttachments
          .getSavedAttachments();

      if (savedAttachmentList.isEmpty) {
        return;
      }

      final List<SavedAttachment> newSavedAttachmentList = [];

      for (final element in savedAttachmentList) {
        if (element.fileName!.split('.').length >= 2) {
          String ext = element.fileName!.split('.').last;
          final String name = element.fileName!.split('.').first;

          if (ext == 'webm') {
            ext = 'mp4';
          }

          final newFileName = '$name.$ext';

          element.fileName = newFileName;

          newSavedAttachmentList.add(element);
        }
      }

      savedAttachments.setList(newSavedAttachmentList);
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
      if (!mounted) return;
      setState(() {
        _hasPermissionError = true;
        _isLoading = false;
      });
      return;
    }

    if (!mounted) return;

    final savedAttachments = Provider.of<SavedAttachmentsProvider>(
      context,
      listen: false,
    );
    final attachments = savedAttachments.getSavedAttachments();

    setState(() {
      _loadedAttachments = attachments;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeChanger>(context);
    final savedAttachments = Provider.of<SavedAttachmentsProvider>(context);
    final bool isDark = theme.getTheme() == ThemeData.dark();

    final attachments = _loadedAttachments ?? [];
    final bool isEmpty = !_isLoading &&
        !_hasPermissionError &&
        savedAttachments.getSavedAttachments().isEmpty;

    return Scaffold(
      body: CupertinoPageScaffold(
        backgroundColor: AppColors.pageBackground(isDark),
        child: CustomScrollView(
          slivers: [
            CupertinoSliverNavigationBar(
              leading: MediaQuery(
                data: MediaQueryData(
                  textScaler: MediaQuery.textScalerOf(context),
                ),
                child: Transform.translate(
                  offset: const Offset(-16, 0),
                  child: CupertinoNavigationBarBackButton(
                    previousPageTitle: 'Home',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              previousPageTitle: 'Home',
              border: Border.all(color: Colors.transparent),
              largeTitle: MediaQuery(
                data: MediaQueryData(
                  textScaler: MediaQuery.textScalerOf(context),
                ),
                child: Text(
                  'Saved Attachments',
                  style: TextStyle(
                    color: theme.getTheme() == ThemeData.dark()
                        ? CupertinoColors.white
                        : CupertinoColors.black,
                  ),
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        showCupertinoModalPopup(
                          context: context,
                          builder: (BuildContext context) =>
                              CupertinoActionSheet(
                                actions: [
                                  CupertinoActionSheetAction(
                                    child: const Text('Clear bookmarks'),
                                    onPressed: () {
                                      savedAttachments.clearSavedAttachments(
                                        context,
                                      );
                                      Navigator.pop(context);
                                    },
                                  ),
                                ],
                                cancelButton: CupertinoActionSheetAction(
                                  child: const Text('Cancel'),
                                  onPressed: () {
                                    Navigator.pop(context);
                                  },
                                ),
                              ),
                        );
                      },
                      child: const Icon(Icons.more_vert),
                    ),
                  ),
                ],
              ),
              backgroundColor: theme.getTheme() == ThemeData.light()
                  ? AppColors.navigationBackground(false)
                  : AppColors.navigationBackground(true),
            ),
            if (_isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: SizedBox.shrink(),
              )
            else if (_hasPermissionError)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: PermissionDenied(),
              )
            else if (isEmpty)
              SliverFillRemaining(
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
              )
            else
              SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
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
          ],
        ),
      ),
    );
  }
}

