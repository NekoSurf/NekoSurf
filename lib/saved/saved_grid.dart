import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chan/saved/permission_denied.dart';
import 'package:flutter_chan/saved/saved_attachment.dart';
import 'package:flutter_chan/saved/saved_attachments_model.dart';
import 'package:flutter_chan/saved/saved_browsing.dart';
import 'package:flutter_chan/saved/saved_folders.dart';
import 'package:flutter_chan/saved/saved_media_viewer_page.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:provider/provider.dart';

const Color _amber = Color(0xFFFBBF24);

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
  int _sizeKey = -1;

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
      try {
        total += await File(folders.mediaPath(a)).length();
      } catch (_) {
        // Missing files count as zero.
      }
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
    final bool isDark = context.isDark;
    final SavedBrowsing browsing = widget.browsing;
    final provider = Provider.of<SavedAttachmentsProvider>(context);

    if (_isLoading) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverGrid.count(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.78,
          children: [
            for (int i = 0; i < 6; i++)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: DashColors.muted(isDark).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
          ],
        ),
      );
    }

    final SavedFolders? folders = _folders;
    if (_hasPermissionError || folders == null) {
      return const SliverToBoxAdapter(child: PermissionDenied());
    }

    final List<SavedAttachment> all = provider.attachments;
    if (all.isEmpty) {
      return const SliverToBoxAdapter(child: _EmptyState());
    }

    if (_sizeKey != all.length) {
      _sizeKey = all.length;
      _sizeFuture = _totalSize(folders, all);
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
          child: SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              children: [
                _FilterPill(
                  label: 'All',
                  count: all.length,
                  selected: browsing.filter == SavedFilter.all,
                  onTap: () => browsing.setFilter(SavedFilter.all),
                ),
                _FilterPill(
                  label: 'Images',
                  count: images,
                  selected: browsing.filter == SavedFilter.images,
                  onTap: () => browsing.setFilter(SavedFilter.images),
                ),
                _FilterPill(
                  label: 'Videos',
                  count: videos,
                  selected: browsing.filter == SavedFilter.videos,
                  onTap: () => browsing.setFilter(SavedFilter.videos),
                ),
              ],
            ),
          ),
        ),
        if (visible.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 48),
              child: Center(
                child: Text(
                  'Nothing matches your search',
                  style: TextStyle(color: DashColors.muted(isDark)),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.78,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final a = visible[index];
                final String key = a.fileName;
                return _Tile(
                  key: ValueKey(key),
                  thumb: File(folders.thumbnailPath(a)),
                  title: _title(a),
                  ext: key.contains('.')
                      ? key.split('.').last.toUpperCase()
                      : '',
                  isVideo: a.isVideo,
                  isGif: key.toLowerCase().endsWith('.gif'),
                  selecting: browsing.selecting,
                  selected: browsing.selected.contains(key),
                  onTap: () {
                    if (browsing.selecting) {
                      browsing.toggleSelected(key);
                    } else {
                      _openViewer(folders, visible, index);
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
                );
              }, childCount: visible.length),
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
            DashColors.accent2.withValues(alpha: isDark ? 0.18 : 0.28),
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
                    color: DashColors.text(isDark),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  total == 1 ? 'saved file' : 'saved files',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DashColors.text(isDark).withValues(alpha: 0.7),
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
                      color: DashColors.text(isDark).withValues(alpha: 0.65),
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
                            color: DashColors.card(isDark),
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

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? DashColors.accent : DashColors.card(isDark),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? DashColors.accent : DashColors.border(isDark),
          ),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.black : DashColors.text(isDark),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected
                    ? Colors.black.withValues(alpha: 0.6)
                    : DashColors.muted(isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.thumb,
    required this.title,
    required this.ext,
    required this.isVideo,
    required this.isGif,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final File thumb;
  final String title;
  final String ext;
  final bool isVideo;
  final bool isGif;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  Color get _typeColor => isGif
      ? _amber
      : isVideo
      ? DashColors.accent2
      : DashColors.accent;

  String get _typeLabel => isGif
      ? 'GIF'
      : isVideo
      ? 'Video'
      : 'Image';

  Widget _media(bool isDark) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          thumb,
          fit: BoxFit.cover,
          cacheWidth: 500,
          errorBuilder: (_, _, _) => ColoredBox(
            color: DashColors.muted(isDark).withValues(alpha: 0.12),
            child: Icon(CupertinoIcons.photo, color: DashColors.muted(isDark)),
          ),
        ),
        if (isVideo && !isGif)
          Center(
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.play_fill,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        if (selecting)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? DashColors.accent
                    : Colors.black.withValues(alpha: 0.35),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: selected
                  ? const Icon(
                      CupertinoIcons.check_mark,
                      color: Colors.black,
                      size: 13,
                    )
                  : null,
            ),
          ),
      ],
    );
  }

  Widget _card(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: DashColors.card(isDark),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: selected ? DashColors.accent : DashColors.border(isDark),
          width: selected ? 2.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: _media(isDark),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: DashColors.text(isDark),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _typeColor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _typeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _typeColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      ext,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: DashColors.muted(isDark),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
        child: _card(context.isDark),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;
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
              tile(-0.14, DashColors.accent, CupertinoIcons.photo_fill),
              Transform.translate(
                offset: const Offset(0, -12),
                child: tile(0, _amber, CupertinoIcons.paperclip),
              ),
              tile(0.14, DashColors.accent2, CupertinoIcons.play_fill),
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
              color: DashColors.text(isDark),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Open an image or video in a thread and tap save to keep it here, available offline.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.4,
              color: DashColors.muted(isDark),
            ),
          ),
        ],
      ),
    );
  }
}
