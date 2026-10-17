import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chan/API/save_videos.dart';
import 'package:flutter_chan/Models/saved_attachment.dart';
import 'package:flutter_chan/blocs/saved_attachments_model.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:flutter_chan/pages/savedAttachments/permission_denied.dart';
import 'package:flutter_chan/pages/savedAttachments/saved_media_viewer_page.dart';
import 'package:provider/provider.dart';

const Color _amber = Color(0xFFFBBF24);

class SavedAttachments extends StatefulWidget {
  const SavedAttachments({Key? key}) : super(key: key);

  @override
  State<SavedAttachments> createState() => _SavedAttachmentsState();
}

class _SavedAttachmentsState extends State<SavedAttachments>
    with WidgetsBindingObserver {
  Directory directory = Directory('');

  bool _isLoading = true;
  bool _hasPermissionError = false;

  Future<int>? _sizeFuture;
  int _sizeKey = -1;

  String _key(SavedAttachment a) => a.fileName?.split('/').last ?? '';

  String _title(SavedAttachment a) {
    final String name = a.originalName ?? _key(a);
    final int dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  String _thumbPath(SavedAttachment a) => savedThumbnailPath(directory.path, a);

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
    // Files may have been deleted in the Files app while backgrounded.
    if (state == AppLifecycleState.resumed && !_isLoading) {
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
    await Provider.of<SavedAttachmentsProvider>(
      context,
      listen: false,
    ).reconcileWithDisk(directory.path);
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

    setState(() => _isLoading = false);
  }

  Future<int> _totalSize(List<SavedAttachment> all) async {
    int total = 0;
    for (final a in all) {
      try {
        total += await File(savedMediaPath(directory.path, _key(a))).length();
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

  Future<void> _openViewer(List<SavedAttachment> items, int index) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SavedMediaViewerPage(
          attachments: items,
          initialIndex: index,
          directoryPath: directory.path,
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
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

    if (_hasPermissionError) {
      return const SliverToBoxAdapter(child: PermissionDenied());
    }

    final List<SavedAttachment> all = provider.getSavedAttachments();
    if (all.isEmpty) {
      return SliverToBoxAdapter(child: _EmptyState(isDark: isDark));
    }

    if (_sizeKey != all.length) {
      _sizeKey = all.length;
      _sizeFuture = _totalSize(all);
    }

    final List<SavedAttachment> visible = provider.visibleAttachments();
    final int videos = all
        .where((a) => a.savedAttachmentType == SavedAttachmentType.Video)
        .length;
    final int images = all.length - videos;

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: _SummaryCard(
            isDark: isDark,
            total: all.length,
            images: images,
            videos: videos,
            sizeFuture: _sizeFuture,
            format: _formatBytes,
            previews: [
              for (final a in all.reversed.take(3)) File(_thumbPath(a)),
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
                  selected: provider.filter == SavedFilter.all,
                  isDark: isDark,
                  onTap: () => provider.setFilter(SavedFilter.all),
                ),
                _FilterPill(
                  label: 'Images',
                  count: images,
                  selected: provider.filter == SavedFilter.images,
                  isDark: isDark,
                  onTap: () => provider.setFilter(SavedFilter.images),
                ),
                _FilterPill(
                  label: 'Videos',
                  count: videos,
                  selected: provider.filter == SavedFilter.videos,
                  isDark: isDark,
                  onTap: () => provider.setFilter(SavedFilter.videos),
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
                final String key = _key(a);
                return _Tile(
                  key: ValueKey(key),
                  thumb: File(_thumbPath(a)),
                  title: _title(a),
                  ext: (a.fileName ?? '').contains('.')
                      ? (a.fileName ?? '').split('.').last.toUpperCase()
                      : '',
                  isVideo: a.savedAttachmentType == SavedAttachmentType.Video,
                  isGif: (a.fileName ?? '').toLowerCase().endsWith('.gif'),
                  selecting: provider.selecting,
                  selected: provider.selected.contains(key),
                  isDark: isDark,
                  onTap: () {
                    if (provider.selecting) {
                      provider.toggleSelected(key);
                    } else {
                      _openViewer(visible, index);
                    }
                  },
                  onLongPress: () {
                    if (provider.selecting) {
                      return;
                    }
                    HapticFeedback.selectionClick();
                    provider.setSelecting(true);
                    provider.toggleSelected(key);
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
    required this.isDark,
    required this.total,
    required this.images,
    required this.videos,
    required this.sizeFuture,
    required this.format,
    required this.previews,
  });

  final bool isDark;
  final int total;
  final int images;
  final int videos;
  final Future<int>? sizeFuture;
  final String Function(int) format;
  final List<File> previews;

  @override
  Widget build(BuildContext context) {
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
                          errorBuilder: (_, __, ___) => ColoredBox(
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
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
    Key? key,
    required this.thumb,
    required this.title,
    required this.ext,
    required this.isVideo,
    required this.isGif,
    required this.selecting,
    required this.selected,
    required this.isDark,
    required this.onTap,
    required this.onLongPress,
  }) : super(key: key);

  final File thumb;
  final String title;
  final String ext;
  final bool isVideo;
  final bool isGif;
  final bool selecting;
  final bool selected;
  final bool isDark;
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

  Widget _media() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          thumb,
          fit: BoxFit.cover,
          cacheWidth: 500,
          errorBuilder: (_, __, ___) => ColoredBox(
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

  Widget _card() {
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
              child: _media(),
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
        child: _card(),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isDark});

  final bool isDark;

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
