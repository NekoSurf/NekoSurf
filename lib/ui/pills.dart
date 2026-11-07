import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/ui/colors.dart';

class RepliesRow extends StatelessWidget {
  const RepliesRow({super.key, this.replies, this.imageReplies});

  /// Null while unknown.
  final int? replies;
  final int? imageReplies;

  @override
  Widget build(BuildContext context) {
    Widget buildChip(IconData icon, int? value, Color color) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              '${value ?? '-'}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        buildChip(CupertinoIcons.reply, replies, DashColors.accent),
        const SizedBox(width: 8),
        buildChip(CupertinoIcons.camera, imageReplies, DashColors.accent2),
      ],
    );
  }
}

class BoardPill extends StatelessWidget {
  const BoardPill({super.key, required this.board});

  final String board;

  @override
  Widget build(BuildContext context) {
    final Color tint = boardColor(board);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '/$board/',
        style: TextStyle(
          color: tint,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// A board's name, big, as far as it fits a page's badge.
class BoardBadge extends StatelessWidget {
  const BoardBadge({super.key, required this.board});

  final String board;

  @override
  Widget build(BuildContext context) {
    return Text(
      '/$board/',
      style: TextStyle(
        fontSize: board.length > 3 ? 13 : 17,
        fontWeight: FontWeight.w800,
        color: boardColor(board),
      ),
    );
  }
}

class PostNumberPill extends StatelessWidget {
  const PostNumberPill({super.key, required this.no});

  final int no;

  @override
  Widget build(BuildContext context) {
    final Color muted = DashColors.muted(context.isDark);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: muted.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'No.$no',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: muted,
        ),
      ),
    );
  }
}

enum MediaFilter {
  all,
  images,
  videos;

  bool shows({required bool isVideo}) => switch (this) {
    MediaFilter.all => true,
    MediaFilter.images => !isVideo,
    MediaFilter.videos => isVideo,
  };
}

/// Pills to choose between everything, only the images and only the videos,
/// each with how many there are.
class MediaFilterPills extends StatelessWidget {
  const MediaFilterPills({
    super.key,
    required this.filter,
    required this.images,
    required this.videos,
    required this.onChanged,
    this.sidePadding = 16,
  });

  final MediaFilter filter;
  final int images;
  final int videos;
  final ValueChanged<MediaFilter> onChanged;
  final double sidePadding;

  @override
  Widget build(BuildContext context) {
    Widget pill(String label, int count, MediaFilter value) => _FilterPill(
      label: label,
      count: count,
      selected: filter == value,
      onTap: () => onChanged(value),
    );

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(sidePadding, 0, sidePadding, 8),
        children: [
          pill('All', images + videos, MediaFilter.all),
          pill('Images', images, MediaFilter.images),
          pill('Videos', videos, MediaFilter.videos),
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
                color: selected
                    ? CupertinoColors.black
                    : DashColors.text(isDark),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected
                    ? CupertinoColors.black.withValues(alpha: 0.6)
                    : DashColors.muted(isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
