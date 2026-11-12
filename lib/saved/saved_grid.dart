import 'dart:io';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chan/media/image_size.dart';
import 'package:flutter_chan/saved/permission_denied.dart';
import 'package:flutter_chan/saved/saved_attachment.dart';
import 'package:flutter_chan/saved/saved_attachments_model.dart';
import 'package:flutter_chan/saved/saved_browsing.dart';
import 'package:flutter_chan/saved/saved_folders.dart';
import 'package:flutter_chan/saved/saved_media_viewer_page.dart';
import 'package:flutter_chan/sync/cloud_sync.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/image_frost.dart';
import 'package:flutter_chan/ui/pills.dart';
import 'package:flutter_chan/ui/toast.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

const Color _amber = Color(0xFFFBBF24);
// As on the cards of a board's grid.
const Color _chipTint = Color(0x40000000);
const double _radius = 22;
const double _gap = 10;
// Where the type chip and the button in the other corner sit on the tile.
const double _chipInset = 10;

// How tall and how wide a tile can be for its picture, width over height:
// a long strip would leave no room for its chips and name.
const double _tallest = 0.6;
const double _widest = 1.1;

class SavedGrid extends StatefulWidget {
  const SavedGrid({super.key, required this.browsing});

  final SavedBrowsing browsing;

  @override
  State<SavedGrid> createState() => _SavedGridState();
}

class _SavedGridState extends State<SavedGrid> with WidgetsBindingObserver {
  // Null until they're open: without them every saved file would look deleted.
  SavedFolders? _folders;

  bool _isLoading = true;
  bool _hasPermissionError = false;

  Future<int>? _sizeFuture;

  /// What the size was added up for: which files, and which of them were
  /// here, as a placeholder's file counts once it's come down.
  int? _sizeKey;

  /// The width and height of each thumbnail measured so far, by its path;
  /// kept while the app runs, so the tab lays out at once next time.
  static final Map<String, (int, int)> _sizes = {};

  /// How big each saved file is, by its path, from adding them up.
  static final Map<String, int> _bytes = {};
  final Set<String> _measuring = {};

  /// The grid waits for the first measuring, so tiles don't jump about.
  bool _measured = false;

  /// Measures the thumbnails at [paths] not measured yet, from the start of
  /// their files, and lays the grid out again once they all are.
  Future<void> _measure(List<String> paths) async {
    final List<String> todo = [
      for (final String path in paths)
        if (!_sizes.containsKey(path) && _measuring.add(path)) path,
    ];
    for (int i = 0; i < todo.length; i += 32) {
      final List<String> batch = todo.skip(i).take(32).toList();
      final List<(int, int)?> sizes = await Future.wait(
        batch.map((path) => imageSize(File(path))),
      );
      for (int j = 0; j < batch.length; j++) {
        if (sizes[j] case final (int, int) size) {
          _sizes[batch[j]] = size;
        }
      }
    }
    // One that's missing is tried again when the files change.
    _measuring.removeAll(todo);
    if (mounted && (todo.isNotEmpty || !_measured)) {
      setState(() => _measured = true);
    }
  }

  double _ratio(String path) {
    final (int, int)? size = _sizes[path];
    return size == null ? 1 : (size.$1 / size.$2).clamp(_tallest, _widest);
  }

  /// What the line under a file's name says: its extension, its width and
  /// height, and how big it is, as far as they're known.
  String _details(SavedFolders folders, SavedAttachment a) {
    final String name = a.fileName;
    final int dot = name.lastIndexOf('.');
    // A video's own thumbnail is smaller than the video.
    final (int, int)? size = a.hasOwnThumbnail
        ? null
        : _sizes[folders.thumbnailPath(a)];
    final int? bytes = _bytes[folders.mediaPath(a)];
    return [
      if (dot > 0) name.substring(dot + 1).toUpperCase(),
      if (size != null) '${size.$1}×${size.$2}',
      if (bytes != null) _formatBytes(bytes),
    ].join(' · ');
  }

  String _title(SavedAttachment a) {
    final String name = a.fileName;
    final int dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _isLoading) {
      return;
    }
    if (_hasPermissionError) {
      // Access may have been granted in Settings meanwhile. Only check:
      // asking for it again opens Settings again on Android.
      _loadAttachments(ask: false);
    } else {
      // Files may have been deleted in the Files app while backgrounded.
      _reconcile();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isLoading) {
      _loadAttachments();
    }
  }

  Future<void> _reconcile() async {
    final SavedFolders? folders = _folders;
    if (folders != null) {
      await Provider.of<SavedAttachmentsProvider>(
        context,
        listen: false,
      ).reconcileWithDisk(folders);
    }
  }

  Future<void> _loadAttachments({bool ask = true}) async {
    try {
      _folders = await openSavedFolders(ask: ask);
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
      _hasPermissionError = false;
      _isLoading = false;
    });
  }

  Future<int> _totalSize(
    SavedFolders folders,
    List<SavedAttachment> all,
  ) async {
    int total = 0;
    for (final a in all) {
      final String path = folders.mediaPath(a);
      try {
        final int bytes = await File(path).length();
        _bytes[path] = bytes;
        total += bytes;
      } catch (_) {
        // Missing files count as zero.
      }
    }
    // For the line under each name.
    if (mounted) {
      setState(() {});
    }
    return total;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  void _openViewer(
    SavedFolders folders,
    List<SavedAttachment> items,
    int index,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SavedMediaViewerPage(
          attachments: items,
          initialIndex: index,
          folders: folders,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SavedBrowsing browsing = widget.browsing;
    final provider = Provider.of<SavedAttachmentsProvider>(context);

    // As many as fit, as on a board's grid: two on a phone, more on an iPad.
    final int columns = max(
      2,
      (MediaQuery.sizeOf(context).width / 230).floor(),
    );

    final Widget placeholder = SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverMasonryGrid.count(
        crossAxisCount: columns,
        mainAxisSpacing: _gap,
        crossAxisSpacing: _gap,
        childCount: 3 * columns,
        itemBuilder: (context, i) => AspectRatio(
          aspectRatio: const [0.75, 1.0, 1.25][i % 3],
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: DashColors.muted(context).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(_radius),
            ),
          ),
        ),
      ),
    );

    if (_isLoading) {
      return placeholder;
    }

    final SavedFolders? folders = _folders;
    if (_hasPermissionError || folders == null) {
      return const SliverToBoxAdapter(child: PermissionDenied());
    }

    final List<SavedAttachment> all = provider.attachments;
    if (all.isEmpty) {
      return const SliverToBoxAdapter(child: _EmptyState());
    }

    final int sizeKey = Object.hashAll(<Object>[
      for (final SavedAttachment a in all) (a.fileName, provider.hasFile(a)),
    ]);
    if (_sizeKey != sizeKey) {
      _sizeKey = sizeKey;
      _sizeFuture = _totalSize(folders, all);
      _measure([for (final a in all) folders.thumbnailPath(a)]);
    }
    if (!_measured) {
      return placeholder;
    }

    final List<SavedAttachment> visible = browsing.visible(all);
    final int videos = all.where((a) => a.isVideo).length;
    final int images = all.length - videos;

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: _SummaryCard(
            total: all.length,
            images: images,
            videos: videos,
            sizeFuture: _sizeFuture,
            format: _formatBytes,
            previews: [
              for (final a in all.reversed.take(3))
                File(folders.thumbnailPath(a)),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        SliverToBoxAdapter(
          child: MediaFilterPills(
            filter: browsing.filter,
            images: images,
            videos: videos,
            onChanged: browsing.setFilter,
          ),
        ),
        if (visible.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 48),
              child: Center(
                child: Text(
                  'Nothing matches your search',
                  style: TextStyle(color: DashColors.muted(context)),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            sliver: SliverMasonryGrid.count(
              crossAxisCount: columns,
              mainAxisSpacing: _gap,
              crossAxisSpacing: _gap,
              childCount: visible.length,
              itemBuilder: (context, index) {
                final a = visible[index];
                final String key = a.fileName;
                final bool here = provider.hasFile(a);
                final String thumb = folders.thumbnailPath(a);
                return AspectRatio(
                  key: ValueKey(key),
                  aspectRatio: _ratio(thumb),
                  child: _Tile(
                    syncKey: a.id,
                    coming: here
                        ? null
                        : provider.isInICloud(a)
                        ? _Coming.inICloud
                        : _Coming.goingUpElsewhere,
                    thumb: File(thumb),
                    title: _title(a),
                    details: _details(folders, a),
                    isVideo: a.isVideo,
                    isGif: key.toLowerCase().endsWith('.gif'),
                    selecting: browsing.selecting,
                    selected: browsing.selected.contains(key),
                    onTap: () {
                      if (browsing.selecting) {
                        browsing.toggleSelected(key);
                      } else if (!here) {
                        showToast(
                          context,
                          provider.isInICloud(a) ||
                                  CloudSync.instance.fileDownload(a.id) != null
                              ? 'Still downloading from iCloud'
                              : 'Still uploading from your other device',
                        );
                      } else {
                        final List<SavedAttachment> openable = visible
                            .where(provider.hasFile)
                            .toList();
                        _openViewer(folders, openable, openable.indexOf(a));
                      }
                    },
                    onLongPress: () {
                      if (browsing.selecting) {
                        return;
                      }
                      HapticFeedback.selectionClick();
                      browsing.setSelecting(true);
                      browsing.toggleSelected(key);
                    },
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.total,
    required this.images,
    required this.videos,
    required this.sizeFuture,
    required this.format,
    required this.previews,
  });

  final int total;
  final int images;
  final int videos;
  final Future<int>? sizeFuture;
  final String Function(int) format;
  final List<File> previews;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;
    const angles = [-0.2, 0.05, 0.22];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(20, 18, 8, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _amber.withValues(alpha: isDark ? 0.22 : 0.35),
            context.accent2.withValues(alpha: isDark ? 0.18 : 0.28),
          ],
        ),
        border: Border.all(color: _amber.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$total',
                  style: TextStyle(
                    fontSize: 44,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.5,
                    color: DashColors.text(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  total == 1 ? 'saved file' : 'saved files',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DashColors.text(context).withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 12),
                FutureBuilder<int>(
                  future: sizeFuture,
                  builder: (context, snapshot) => Text(
                    '$images images · $videos videos'
                    '${snapshot.hasData ? ' · ${format(snapshot.data!)}' : ''}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: DashColors.text(context).withValues(alpha: 0.65),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 112,
            height: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (int i = previews.length - 1; i >= 0; i--)
                  Transform.translate(
                    offset: Offset((i - 1) * 14.0, 0),
                    child: Transform.rotate(
                      angle: angles[i],
                      child: Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.file(
                          previews[i],
                          fit: BoxFit.cover,
                          cacheWidth: 200,
                          errorBuilder: (_, _, _) => ColoredBox(
                            color: DashColors.card(context),
                            child: const Icon(
                              CupertinoIcons.photo,
                              color: _amber,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Where the file of a saved attachment from another device is, while it
/// isn't here.
enum _Coming { goingUpElsewhere, inICloud }

class _Tile extends StatelessWidget {
  const _Tile({
    required this.syncKey,
    required this.coming,
    required this.thumb,
    required this.title,
    required this.details,
    required this.isVideo,
    required this.isGif,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  /// Its key in iCloud sync, to show whether it has gone up yet.
  final String syncKey;

  /// Null when its file is here.
  final _Coming? coming;
  final File thumb;
  final String title;
  final String details;
  final bool isVideo;
  final bool isGif;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  Color _typeColor(BuildContext context) => isGif
      ? _amber
      : isVideo
      ? context.accent2
      : context.accent;

  String get _typeLabel => isGif
      ? 'GIF'
      : isVideo
      ? 'Video'
      : 'Image';

  IconData get _typeIcon => isGif
      ? CupertinoIcons.sparkles
      : isVideo
      ? CupertinoIcons.play_fill
      : CupertinoIcons.photo_fill;

  Widget _card(BuildContext context) {
    final bool isDark = context.isDark;
    final Color cardColor = DashColors.card(context);
    final ImageProvider frost = FileImage(thumb);

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(
          color: selected ? context.accent : DashColors.border(context),
          width: selected ? 2.5 : 1,
        ),
        boxShadow: DashColors.cardShadow(isDark),
      ),
      child: ClipRRect(
        // Inside the border.
        borderRadius: BorderRadius.circular(_radius - (selected ? 2.5 : 1)),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final Size card = constraints.biggest;
            return Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  // Dimmed till its file is here.
                  opacity: coming == null ? 1 : 0.55,
                  child: Image.file(
                    thumb,
                    fit: BoxFit.cover,
                    cacheWidth: 500,
                    errorBuilder: (_, _, _) => ColoredBox(
                      color: DashColors.muted(context).withValues(alpha: 0.12),
                      child: Icon(
                        CupertinoIcons.photo,
                        color: DashColors.muted(context),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: _chipInset,
                  top: _chipInset,
                  child: ImageFrost(
                    image: frost,
                    card: card,
                    anchor: Alignment.topLeft,
                    inset: const Offset(-_chipInset, -_chipInset),
                    radius: 8,
                    tint: _chipTint,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_typeIcon, color: _typeColor(context), size: 12),
                        const SizedBox(width: 4),
                        Text(
                          _typeLabel,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Where a board's card has its bookmark button: whether it's
                // picked while picking files, or else how it stands with
                // iCloud.
                Positioned(
                  right: _chipInset,
                  top: _chipInset,
                  child: selecting
                      ? _CornerButton(
                          frost: frost,
                          card: card,
                          child: Icon(
                            selected
                                ? CupertinoIcons.check_mark_circled_solid
                                : CupertinoIcons.circle,
                            color: selected ? context.accent : Colors.white,
                            size: 18,
                          ),
                        )
                      : _SyncBadge(
                          syncKey: syncKey,
                          coming: coming,
                          frost: frost,
                          card: card,
                        ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ImageFrost(
                    image: frost,
                    card: card,
                    anchor: Alignment.bottomCenter,
                    inset: Offset.zero,
                    radius: 0,
                    tint: cardColor.withValues(alpha: isDark ? 0.7 : 0.85),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: DashColors.text(context),
                          ),
                        ),
                        if (details.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            details,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: DashColors.muted(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedScale(
        scale: selected ? 0.95 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: _card(context),
      ),
    );
  }
}

/// With iCloud sync on, how a saved file stands with it. One saved here
/// that isn't in iCloud yet: a cloud while it waits its turn, then a ring
/// filling as it goes up. One saved on another device: a cloud while it
/// goes up from there, a cloud with an arrow while it waits to come down,
/// then a ring filling as it does.
class _SyncBadge extends StatelessWidget {
  const _SyncBadge({
    required this.syncKey,
    required this.coming,
    required this.frost,
    required this.card,
  });

  final String syncKey;
  final _Coming? coming;
  final ImageProvider frost;
  final Size card;

  @override
  Widget build(BuildContext context) {
    final CloudSync sync = CloudSync.instance;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final ({IconData icon, double? progress, String label})? badge = _badge(
          sync,
        );
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: badge == null
              ? const SizedBox.shrink()
              : Semantics(
                  key: ValueKey(badge.label),
                  label: badge.label,
                  child: _CornerButton(
                    frost: frost,
                    card: card,
                    child: badge.progress == null
                        ? Icon(badge.icon, color: Colors.white, size: 16)
                        : _UploadRing(value: badge.progress!),
                  ),
                ),
        );
      },
    );
  }

  ({IconData icon, double? progress, String label})? _badge(CloudSync sync) {
    switch (coming) {
      case null:
        final FileUpload? upload = sync.fileUpload(syncKey);
        if (upload == null) {
          return null;
        }
        final double? progress = upload.progress;
        return (
          icon: CupertinoIcons.cloud_upload,
          progress: progress,
          label: progress == null
              ? 'Waiting to go up to iCloud'
              : 'Going up to iCloud, ${(progress * 100).round()}%',
        );
      case _Coming.goingUpElsewhere || _Coming.inICloud:
        // Its file can be there, coming down, before its record says so.
        final FileDownload? download = sync.fileDownload(syncKey);
        if (download == null && coming == _Coming.goingUpElsewhere) {
          return (
            icon: CupertinoIcons.cloud,
            progress: null,
            label: 'Going up to iCloud from another device',
          );
        }
        final double? progress = download?.progress;
        return (
          icon: CupertinoIcons.cloud_download,
          progress: progress,
          label: progress == null
              ? 'Waiting to come down from iCloud'
              : 'Coming down from iCloud, ${(progress * 100).round()}%',
        );
    }
  }
}

/// A frosted square in a tile's top right corner, like a board card's
/// bookmark button.
class _CornerButton extends StatelessWidget {
  const _CornerButton({
    required this.frost,
    required this.card,
    required this.child,
  });

  final ImageProvider frost;
  final Size card;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ImageFrost(
      image: frost,
      card: card,
      anchor: Alignment.topRight,
      inset: const Offset(_chipInset, -_chipInset),
      radius: 8,
      tint: _chipTint,
      child: SizedBox.square(dimension: 32, child: Center(child: child)),
    );
  }
}

class _UploadRing extends StatelessWidget {
  const _UploadRing({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    // Eases between updates, which come about twice a second.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      builder: (context, value, _) => SizedBox.square(
        dimension: 16,
        child: CircularProgressIndicator(
          value: value,
          strokeWidth: 2.2,
          strokeCap: StrokeCap.round,
          color: Colors.white,
          backgroundColor: Colors.white.withValues(alpha: 0.25),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    Widget tile(double angle, Color color, IconData icon) => Transform.rotate(
      angle: angle,
      child: Container(
        width: 74,
        height: 74,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, size: 30, color: color),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 56, 32, 0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              tile(-0.14, context.accent, CupertinoIcons.photo_fill),
              Transform.translate(
                offset: const Offset(0, -12),
                child: tile(0, _amber, CupertinoIcons.paperclip),
              ),
              tile(0.14, context.accent2, CupertinoIcons.play_fill),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            'Your collection starts here',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: DashColors.text(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Open an image or video in a thread and tap save to keep it here, available offline.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.4,
              color: DashColors.muted(context),
            ),
          ),
        ],
      ),
    );
  }
}
