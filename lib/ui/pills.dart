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
