import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/widgets/interactive/glass_chip.dart';

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
      return GlassChip(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        icon: Icon(icon, size: 12),
        label: '$value',
        labelStyle: const TextStyle(fontSize: 12),
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
