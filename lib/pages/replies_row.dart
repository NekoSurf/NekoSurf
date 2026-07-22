import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class RepliesRow extends StatelessWidget {
  const RepliesRow({
    Key? key,
    this.replies = '-',
    this.imageReplies = '-',
    this.showImageReplies = true,
  }) : super(key: key);

  final dynamic replies;
  final dynamic imageReplies;
  final bool showImageReplies;

  @override
  Widget build(BuildContext context) {
    Widget buildChip(IconData icon, dynamic value) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: CupertinoColors.systemFill.resolveFrom(context),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12),
            const SizedBox(width: 4),
            Text('$value', style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
    }

    return Row(
      children: [
        buildChip(CupertinoIcons.reply, replies),
        if (showImageReplies) ...[
          const SizedBox(width: 8),
          buildChip(CupertinoIcons.camera, imageReplies),
        ],
      ],
    );
  }
}
