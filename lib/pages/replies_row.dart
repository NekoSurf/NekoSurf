import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';

class RepliesRow extends StatelessWidget {
  const RepliesRow({
    super.key,
    this.replies = '-',
    this.imageReplies = '-',
    this.showImageReplies = true,
  });

  final dynamic replies;
  final dynamic imageReplies;
  final bool showImageReplies;

  @override
  Widget build(BuildContext context) {
    Widget buildChip(IconData icon, dynamic value, Color color) {
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
              '$value',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        buildChip(CupertinoIcons.reply, replies, DashColors.accent),
        if (showImageReplies) ...[
          const SizedBox(width: 8),
          buildChip(CupertinoIcons.camera, imageReplies, DashColors.accent2),
        ],
      ],
    );
  }
}
