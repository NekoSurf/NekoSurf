import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:provider/provider.dart';

class RepliesRow extends StatelessWidget {
  const RepliesRow({
    Key? key,
    this.replies = '-',
    this.imageReplies = '-',
    this.showImageReplies = true,
    this.invertTextColor = false,
  }) : super(key: key);

  final dynamic replies;
  final dynamic imageReplies;
  final bool showImageReplies;
  final bool invertTextColor;

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeChanger>(context);
    final bool isDark = theme.getTheme() == ThemeData.dark();
    final Color fg = invertTextColor
        ? (isDark ? CupertinoColors.black : CupertinoColors.white)
        : (isDark ? CupertinoColors.white : CupertinoColors.black);
    final Color chipBg = isDark
        ? CupertinoColors.systemGrey.withValues(alpha: 0.2)
        : CupertinoColors.systemGrey6;

    Widget buildChip(IconData icon, dynamic value) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: chipBg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: fg, size: 12),
            const SizedBox(width: 4),
            Text(
              '$value',
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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
