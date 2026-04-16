import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_chan/API/save_videos.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/Models/saved_attachment.dart';
import 'package:flutter_chan/blocs/saved_attachments_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/pages/media_page.dart';
import 'package:flutter_chan/pages/savedAttachments/permission_denied.dart';
import 'package:provider/provider.dart';

class SavedAttachments extends StatefulWidget {
  const SavedAttachments({Key? key}) : super(key: key);

  @override
  State<SavedAttachments> createState() => _SavedAttachmentsState();
}

class _SavedAttachmentsState extends State<SavedAttachments> {
  final ScrollController scrollController = ScrollController();

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

    return Scaffold(
      body: CupertinoPageScaffold(
        backgroundColor: theme.getTheme() == ThemeData.light()
            ? CupertinoColors.systemGroupedBackground
            : CupertinoColors.black,
        child: CustomScrollView(
          slivers: [
            CupertinoSliverNavigationBar(
              leading: MediaQuery(
                data: MediaQueryData(
                  textScaler: TextScaler.linear(
                    MediaQuery.textScaleFactorOf(context),
                  ),
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
                  textScaler: TextScaler.linear(
                    MediaQuery.textScaleFactorOf(context),
                  ),
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
                  ? CupertinoColors.systemGroupedBackground.withValues(
                      alpha: 0.7,
                    )
                  : CupertinoColors.black.withOpacity(0.7),
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
                                        for (final SavedAttachment attachment
                                            in snapshot.data ?? [])
                                          GestureDetector(
                                            onTap: () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (context) =>
                                                      MediaPage(
                                                        video:
                                                            attachment
                                                                .fileName ??
                                                            '',
                                                        allPosts: getList(
                                                          snapshot.data,
                                                        ),
                                                        isAsset: true,
                                                        directory: directory,
                                                      ),
                                                ),
                                              );
                                            },
                                            child: Container(
                                              decoration: BoxDecoration(
                                                image: DecorationImage(
                                                  fit: BoxFit.cover,
                                                  image: FileImage(
                                                    File(
                                                      '${directory.path}/savedAttachments/${attachment.thumbnail}',
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              child:
                                                  attachment
                                                          .savedAttachmentType ==
                                                      SavedAttachmentType.Video
                                                  ? Center(
                                                      child: Icon(
                                                        CupertinoIcons.play,
                                                        color: Colors.white,
                                                        size: 50,
                                                        shadows: [
                                                          Shadow(
                                                            blurRadius: 10,
                                                            color: Colors.black
                                                                .withOpacity(
                                                                  .6,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                    )
                                                  : Container(),
                                            ),
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
