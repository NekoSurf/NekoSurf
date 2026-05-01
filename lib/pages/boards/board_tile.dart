import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/board.dart';
import 'package:flutter_chan/blocs/favorite_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/pages/board/board_page.dart';
import 'package:flutter_chan/services/string.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

Color _boardColor(String board, bool isNSFW) {
  const colors = [
    Color.fromARGB(255, 25, 190, 143),
    Color(0xFF1E88E5),
    Color(0xFF43A047),
    Color(0xFF6D4C41),
    Color(0xFF00897B),
    Color(0xFF3949AB),
    Color(0xFF5E35B1),
  ];

  const nsfwColors = [Color(0xFFE53935)];

  final hash = board.codeUnits.fold(0, (prev, e) => prev + e);
  return isNSFW
      ? nsfwColors[hash % nsfwColors.length]
      : colors[hash % colors.length];
}

class BoardTile extends StatefulWidget {
  const BoardTile({Key? key, required this.board, required this.favorites})
    : super(key: key);

  final Board board;
  final bool favorites;

  @override
  State<BoardTile> createState() => _BoardTileState();
}

class _BoardTileState extends State<BoardTile> {
  bool isFavorite = false;

  @override
  Widget build(BuildContext context) {
    final favorites = Provider.of<FavoriteProvider>(context);
    final theme = Provider.of<ThemeChanger>(context);
    final bool isDark = theme.getTheme() == ThemeData.dark();

    isFavorite = favorites.getFavorites().contains(widget.board.board);

    final boardCode = widget.board.board ?? '';
    final color = _boardColor(boardCode, widget.board.wsBoard == 0);
    final displayCode = boardCode.length > 3
        ? boardCode.substring(0, 3)
        : boardCode;

    return Slidable(
      endActionPane: isFavorite
          ? ActionPane(
              extentRatio: 0.28,
              motion: const BehindMotion(),
              children: [
                SlidableAction(
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(14),
                  ),
                  label: 'Remove',
                  backgroundColor: const Color(0xFFE53935),
                  foregroundColor: Colors.white,
                  icon: CupertinoIcons.heart_slash_fill,
                  onPressed: (context) => {
                    favorites.removeFavorites(boardCode),
                  },
                ),
              ],
            )
          : ActionPane(
              extentRatio: 0.28,
              motion: const BehindMotion(),
              children: [
                SlidableAction(
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(14),
                  ),
                  label: 'Favorite',
                  backgroundColor: const Color(0xFF43A047),
                  foregroundColor: Colors.white,
                  icon: CupertinoIcons.heart_fill,
                  onPressed: (context) => {favorites.addFavorites(boardCode)},
                ),
              ],
            ),
      child: CupertinoListTile.notched(
        leading: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            '/$displayCode/',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                widget.board.title ?? '',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (widget.board.wsBoard == 0)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemRed.withValues(
                      alpha: isDark ? 0.25 : 0.12,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'NSFW',
                    style: TextStyle(
                      color: CupertinoColors.systemRed,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          cleanTags(unescape(widget.board.metaDescription ?? '')),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: TextStyle(
            fontSize: 12.5,
            color: isDark
                ? CupertinoColors.systemGrey
                : CupertinoColors.systemGrey,
          ),
        ),
        trailing: const CupertinoListTileChevron(),
        onTap: () => {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => BoardPage(
                boardName: widget.board.title ?? '',
                board: widget.board.board ?? '',
              ),
            ),
          ),
        },
      ),
    );
  }
}
