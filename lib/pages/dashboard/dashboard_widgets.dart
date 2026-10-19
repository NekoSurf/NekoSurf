import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/blocs/history_model.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:flutter_chan/services/string.dart';
import 'package:flutter_chan/widgets/dash_dialogs.dart';

class DashCard extends StatelessWidget {
  const DashCard({
    Key? key,
    required this.isDark,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.onTap,
    this.radius = 20,
  }) : super(key: key);

  final bool isDark;
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: DashColors.card(isDark),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: DashColors.border(isDark)),
        ),
        child: child,
      ),
    );
  }
}

class DashSectionHeader extends StatelessWidget {
  const DashSectionHeader({
    Key? key,
    required this.title,
    required this.isDark,
    this.actionLabel,
    this.onAction,
  }) : super(key: key);

  final String title;
  final bool isDark;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: DashColors.text(isDark),
              ),
            ),
          ),
          if (actionLabel != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionLabel!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: DashColors.accent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DashHero extends StatelessWidget {
  const DashHero({
    Key? key,
    required this.isDark,
    required this.favorites,
    required this.bookmarks,
    required this.saved,
    required this.onFavorites,
    required this.onBookmarks,
    required this.onSaved,
  }) : super(key: key);

  final bool isDark;
  final int favorites;
  final int bookmarks;
  final int saved;
  final VoidCallback onFavorites;
  final VoidCallback onBookmarks;
  final VoidCallback onSaved;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  DashColors.accent.withValues(alpha: 0.22),
                  DashColors.accent2.withValues(alpha: 0.18),
                ]
              : [
                  DashColors.accent.withValues(alpha: 0.35),
                  DashColors.accent2.withValues(alpha: 0.28),
                ],
        ),
        border: Border.all(color: DashColors.accent.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -50,
            top: -60,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    DashColors.accent2.withValues(alpha: 0.35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: DashColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'NEKOSURF',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        color: DashColors.text(isDark).withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _Stat(
                      isDark: isDark,
                      icon: CupertinoIcons.heart_fill,
                      color: const Color(0xFFF472B6),
                      value: favorites,
                      label: 'Boards',
                      onTap: onFavorites,
                    ),
                    const SizedBox(width: 8),
                    _Stat(
                      isDark: isDark,
                      icon: CupertinoIcons.bookmark_fill,
                      color: DashColors.accent,
                      value: bookmarks,
                      label: 'Bookmarks',
                      onTap: onBookmarks,
                    ),
                    const SizedBox(width: 8),
                    _Stat(
                      isDark: isDark,
                      icon: CupertinoIcons.paperclip,
                      color: const Color(0xFFFBBF24),
                      value: saved,
                      label: 'Saved',
                      onTap: onSaved,
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
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.isDark,
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final bool isDark;
  final IconData icon;
  final Color color;
  final int value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withValues(alpha: 0.28)
                : Colors.white.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 13, color: color),
                  const SizedBox(width: 6),
                  Text(
                    '$value',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: DashColors.text(isDark),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: DashColors.muted(isDark),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DashFeedCard extends StatelessWidget {
  const DashFeedCard({
    Key? key,
    required this.isDark,
    required this.boardCount,
    required this.onTap,
  }) : super(key: key);

  final bool isDark;
  final int boardCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const Color pink = Color(0xFFF472B6);

    return DashCard(
      isDark: isDark,
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: pink.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              CupertinoIcons.rectangle_stack_fill,
              color: pink,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your feed',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: DashColors.text(isDark),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Latest threads from $boardCount favorite ${boardCount == 1 ? 'board' : 'boards'}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: DashColors.muted(isDark),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            CupertinoIcons.chevron_right,
            size: 15,
            color: DashColors.muted(isDark),
          ),
        ],
      ),
    );
  }
}

class DashThreadCard extends StatelessWidget {
  const DashThreadCard({
    Key? key,
    required this.thread,
    required this.isDark,
    required this.onTap,
    required this.onRemove,
  }) : super(key: key);

  final HistoryThread thread;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final color = boardColor(thread.board);
    final title = unescape(cleanTags(thread.title)).trim();
    final body = unescape(cleanTags(thread.com ?? '')).trim();
    final headline = title.isNotEmpty
        ? title
        : (body.isNotEmpty ? body : 'No.${thread.no}');

    return GestureDetector(
      onTap: onTap,
      onLongPress: () => showDashMenu(
        context,
        title: headline,
        entries: [
          DashMenuEntry(
            title: 'Remove from history',
            icon: CupertinoIcons.trash,
            isDestructive: true,
            onPressed: onRemove,
          ),
        ],
      ),
      child: Container(
        width: 230,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: DashColors.card(isDark),
          border: thread.imageUrl == null
              ? Border.all(color: DashColors.border(isDark))
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thread.imageUrl != null)
              Transform.scale(
                scale: 1.05,
                child: Image.network(
                  'https://i.4cdn.org/${thread.board}/${thread.imageUrl}',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(
                      alpha: thread.imageUrl != null ? 0.05 : 0,
                    ),
                    Colors.black.withValues(alpha: 0.82),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '/${thread.board}/',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeAgo(thread.visitedAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DashBoardChip extends StatelessWidget {
  const DashBoardChip({
    Key? key,
    required this.board,
    required this.title,
    required this.isDark,
    required this.onTap,
    this.nsfw = false,
  }) : super(key: key);

  final String board;
  final String title;
  final bool isDark;
  final bool nsfw;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = boardColor(board, nsfw: nsfw);

    return DashCard(
      isDark: isDark,
      onTap: onTap,
      radius: 16,
      padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 34),
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Text(
              '/$board/',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DashColors.text(isDark),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DashBoardRow extends StatelessWidget {
  const DashBoardRow({
    Key? key,
    required this.board,
    required this.title,
    required this.description,
    required this.isDark,
    required this.isFavorite,
    required this.nsfw,
    required this.onTap,
    required this.onToggleFavorite,
  }) : super(key: key);

  final String board;
  final String title;
  final String description;
  final bool isDark;
  final bool isFavorite;
  final bool nsfw;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final color = boardColor(board, nsfw: nsfw);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(13),
              ),
              alignment: Alignment.center,
              child: Text(
                '/$board/',
                style: TextStyle(
                  fontSize: board.length > 3 ? 10 : 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: DashColors.text(isDark),
                          ),
                        ),
                      ),
                      if (nsfw)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: DashColors.nsfw.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text(
                            'NSFW',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: DashColors.nsfw,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: DashColors.muted(isDark),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.all(6),
              minimumSize: const Size(32, 32),
              onPressed: onToggleFavorite,
              child: Icon(
                isFavorite ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                size: 20,
                color: isFavorite
                    ? const Color(0xFFF472B6)
                    : DashColors.muted(isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DashPageHeader extends StatelessWidget {
  const DashPageHeader({
    Key? key,
    required this.isDark,
    required this.badge,
    required this.color,
    required this.title,
    required this.subtitle,
  }) : super(key: key);

  final bool isDark;
  final Widget badge;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: isDark ? 0.22 : 0.3),
            DashColors.accent2.withValues(alpha: isDark ? 0.12 : 0.18),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(17),
            ),
            alignment: Alignment.center,
            child: badge,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: DashColors.text(isDark),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: DashColors.muted(isDark),
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

class DashSearchField extends StatelessWidget {
  const DashSearchField({
    Key? key,
    required this.isDark,
    required this.controller,
    required this.onChanged,
    this.placeholder = 'Search threads',
  }) : super(key: key);

  final bool isDark;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: CupertinoSearchTextField(
        controller: controller,
        placeholder: placeholder,
        backgroundColor: DashColors.card(isDark),
        onChanged: onChanged,
      ),
    );
  }
}

class DashListSection extends StatelessWidget {
  const DashListSection({Key? key, required this.children, this.header})
    : super(key: key);

  final List<Widget> children;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final bool isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return CupertinoListSection.insetGrouped(
      header: header,
      backgroundColor: Colors.transparent,
      decoration: BoxDecoration(
        color: DashColors.card(isDark),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: DashColors.border(isDark)),
      ),
      children: children,
    );
  }
}
