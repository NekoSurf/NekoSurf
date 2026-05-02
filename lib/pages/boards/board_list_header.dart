import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class BoardListHeader extends StatelessWidget {
  const BoardListHeader({
    Key? key,
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.isDark,
  }) : super(key: key);

  final String title;
  final IconData icon;
  final Color iconColor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: isDark ? 0.2 : 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: iconColor, size: 14),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? CupertinoColors.white : CupertinoColors.black,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}
