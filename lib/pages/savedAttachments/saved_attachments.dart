import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_chan/API/save_videos.dart';
import 'package:flutter_chan/Models/post.dart';
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

  Directory directory = Directory('');

  Future<List<SavedAttachment>> getSavedAttachments(
    BuildContext context,
  ) async {
    try {
      directory = await requestDirectory(
        directory,
        context,
        showErrorDialog: false,
      );
    } catch (e) {
      return Future.error(e.toString());
    }

    final savedAttachments = Provider.of<SavedAttachmentsProvider>(
      context,
      listen: false,
    );
    final List<SavedAttachment> savedAttachmentList = savedAttachments
        .getSavedAttachments();

    return Future.value(savedAttachmentList);
  }

  List<Post> getList(List<SavedAttachment>? savedAttachments) {
    final List<Post> postList = [];

    for (final SavedAttachment savedAttachment in savedAttachments ?? []) {
      final String video = savedAttachment.fileName!.split('/').last;

      final String ext =
          '.${savedAttachment.fileName!.split('/').last.split('.').last}';

      final Post post = Post(
        tim: int.parse(video.split('.').first),
        ext: ext,
        filename: video,
      );

      postList.add(post);
    }

    return postList;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeChanger>(context);
    final savedAttachments = Provider.of<SavedAttachmentsProvider>(context);
    final bool isDark = theme.getTheme() == ThemeData.dark();

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
            SliverList(
              delegate: SliverChildListDelegate([
                FutureBuilder<List<SavedAttachment>>(
                  future: getSavedAttachments(context),
                  builder:
                      (
                        BuildContext context,
                        AsyncSnapshot<List<SavedAttachment>> snapshot,
                      ) {
                        switch (snapshot.connectionState) {
                          case ConnectionState.waiting:
                            return Container();
                          default:
                            if (snapshot.hasError)
                              return const PermissionDenied();
                            else if (savedAttachments
                                .getSavedAttachments()
                                .isEmpty)
                              return Column(
                                children: [
                                  const SizedBox(height: 30),
                                  Text(
                                    'Save Attachments first!',
                                    style: TextStyle(
                                      fontSize: 26,
                                      color:
                                          theme.getTheme() == ThemeData.dark()
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                  ),
                                ],
                              );
                            else
                              return Column(
                                children: [
                                  SizedBox(
                                    child: GridView.count(
                                      physics: const ScrollPhysics(),
                                      shrinkWrap: true,
                                      padding: EdgeInsets.zero,
                                      crossAxisCount: 3,
                                      children: [
                                        for (
                                          int index = 0;
                                          index < (snapshot.data ?? []).length;
                                          index++
                                        )
                                          _buildAttachmentTile(
                                            (snapshot.data ?? [])[index],
                                            snapshot.data ?? [],
                                            index,
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                        }
                      },
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
