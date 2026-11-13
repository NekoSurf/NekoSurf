import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/media/image_cache.dart';
import 'package:flutter_chan/media/reverse_image_search.dart';
import 'package:flutter_chan/media/shared_media_viewer.dart';
import 'package:flutter_chan/media/spoiler_cover.dart';
import 'package:flutter_chan/saved/downloads.dart';
import 'package:flutter_chan/saved/give_media.dart';
import 'package:flutter_chan/saved/media_tasks.dart';
import 'package:flutter_chan/saved/photos_prompt.dart';
import 'package:flutter_chan/saved/report_failure.dart';
import 'package:flutter_chan/saved/saved_attachments_model.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:provider/provider.dart';

class ThreadMediaViewerPage extends StatefulWidget {
  const ThreadMediaViewerPage({
    super.key,
    required this.mediaPosts,
    required this.initialIndex,
    required this.currentPost,
  });

  final List<Post> mediaPosts;
  final int initialIndex;

  /// Told which post is on screen, as the route returns it when closed.
  final ValueNotifier<int?> currentPost;

  @override
  State<ThreadMediaViewerPage> createState() => _ThreadMediaViewerPageState();
}

class _ThreadMediaViewerPageState extends State<ThreadMediaViewerPage> {
  late int _currentIndex = widget.initialIndex;

  // Each upload is on its own, by its `tim`, so several can be under way at
  // once; saving is in SavedAttachmentsProvider.
  final MediaTasks _removals = MediaTasks();
  final MediaTasks _toPhotos = MediaTasks();
  final MediaTasks _shares = MediaTasks();

  @override
  void initState() {
    super.initState();
    widget.currentPost.value = _currentPost.no;
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

  Post get _currentPost => widget.mediaPosts[_currentIndex];

  /// What saving or sharing calls the file.
  String _givenName(Post post) =>
      context.read<SettingsProvider>().serverFileNames.value
      ? post.uploadName
      : post.posterFileName;

  List<SharedMediaViewerItem> get _items {
    return widget.mediaPosts
        .map((Post post) {
          return SharedMediaViewerItem(
            id: '${post.no}',
            name: post.posterFileName,
            source: post.fileUrl,
            isVideo: post.isVideo,
            imageProvider: fullImage(post.fileUrl),
            thumbnail: thumbnailImage(post.thumbnailUrl),
            width: post.w,
            height: post.h,
            spoilerUpload: coveredUpload(context, post),
            coverLabel: coverLabel(post),
          );
        })
        .toList(growable: false);
  }

  // Each of these acts on the post on screen when it's tapped, even if the
  // viewer moves on meanwhile.

  Future<void> _save() async {
    final Post post = _currentPost;
    final SavedAttachmentsProvider saved = context
        .read<SavedAttachmentsProvider>();
    final String name = _givenName(post);
    await reportingFailure(
      context,
      () => saved.save(post, fileName: name),
      message: "Couldn't save it",
    );
  }

  Future<void> _removeFromSaved() async {
    final String key = _currentPost.uploadId;
    final SavedAttachmentsProvider saved = context
        .read<SavedAttachmentsProvider>();
    await reportingFailure(
      context,
      () => _removals.run(key, (_) => saved.remove(key)),
      message: "Couldn't delete it",
    );
  }

  Future<void> _saveToPhotos() async {
    final Post post = _currentPost;
    final String name = _givenName(post);
    if (!await confirmSavingToPhotos(context) || !mounted) {
      return;
    }
    await reportingFailure(
      context,
      () => _toPhotos.run(
        post.uploadId,
        (SaveProgress onProgress) =>
            downloadToPhotos(post.fileUrl, name, onProgress: onProgress),
      ),
    );
  }

  /// Gets the post ready to share, and opens the share sheet for it once
  /// it's free, even if the viewer has moved on by then.
  Future<void> _share() async {
    final Post post = _currentPost;
    final String name = _givenName(post);
    await reportingFailure(
      context,
      () => _shares.run(
        post.uploadId,
        (SaveProgress onProgress) =>
            shareDownload(post.fileUrl, name, onProgress: onProgress),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SavedAttachmentsProvider saved = context
        .watch<SavedAttachmentsProvider>();
    final Post post = _currentPost;
    final String key = post.uploadId;

    return SharedMediaViewer(
      items: _items,
      index: _currentIndex,
      savesData: context.watch<SettingsProvider>().dataSaver.value,
      onClose: () => Navigator.of(context).pop(post.no),
      onIndexChanged: (int index) {
        if (index == _currentIndex) {
          return;
        }
        setState(() {
          _currentIndex = index;
        });
        widget.currentPost.value = _currentPost.no;
      },
      actions: [
        if (saved.contains(key))
          SharedMediaViewerAction(
            icon: CupertinoIcons.trash,
            label: 'Remove from Saved',
            onPressed: (_) => _removeFromSaved(),
            isBusy: _removals.isRunning(key),
          )
        else
          SharedMediaViewerAction(
            icon: CupertinoIcons.add_circled,
            label: 'Save',
            onPressed: (_) => _save(),
            isBusy: saved.saves.isRunning(key),
            progress: saved.saves.progressOf(key),
          ),
        SharedMediaViewerAction(
          icon: CupertinoIcons.arrow_down_to_line,
          label: 'Save to Photos',
          onPressed: (_) => _saveToPhotos(),
          isBusy: _toPhotos.isRunning(key),
          progress: _toPhotos.progressOf(key),
          isCompleted: _toPhotos.isDone(key),
        ),
        SharedMediaViewerAction(
          icon: CupertinoIcons.share,
          label: 'Share',
          onPressed: (_) => _share(),
          isBusy: _shares.isRunning(key),
          progress: _shares.progressOf(key),
        ),
        SharedMediaViewerAction(
          icon: CupertinoIcons.search,
          label: 'Search for this image',
          // Search engines only take images, so videos use their thumbnail.
          onPressed: (BuildContext anchor) => showReverseImageSearchMenu(
            anchor,
            post.isVideo ? post.thumbnailUrl : post.fileUrl,
          ),
        ),
      ],
    );
  }
}
