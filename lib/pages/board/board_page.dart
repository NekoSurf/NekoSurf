import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/constants.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_chan/pages/board/grid_view.dart';
import 'package:flutter_chan/pages/favorite_button.dart';
import 'package:flutter_chan/widgets/reload.dart';
import 'package:provider/provider.dart';

class BoardPage extends StatefulWidget {
  const BoardPage({Key? key, required this.board, required this.boardName})
    : super(key: key);

  final String board;
  final String boardName;

  @override
  BoardPageState createState() => BoardPageState();
}

class BoardPageState extends State<BoardPage> {
  final ScrollController scrollController = ScrollController();
  final TextEditingController _searchBarController = TextEditingController();

  late Future<List<Post>> _fetchAllThreadsFromBoard;

  late List<Post> filteredBoards;

  bool isFavorite = false;
  late Sort sort;

  @override
  void initState() {
    super.initState();

    final settings = Provider.of<SettingsProvider>(context, listen: false);
    sort = settings.getBoardSort();

    loadBoard();
  }

  void loadBoard() {
    final settings = Provider.of<SettingsProvider>(context, listen: false);

    setState(() {
      _fetchAllThreadsFromBoard = fetchAllThreadsFromBoard(
        settings.getBoardSort(),
        widget.board,
      ).then((value) => filteredBoards = value);
    });
  }

  void setSort(Sort sortBy, SettingsProvider settings) {
    setState(() {
      _searchBarController.clear();

      _fetchAllThreadsFromBoard = fetchAllThreadsFromBoard(
        sortBy,
        widget.board,
      ).then((value) => filteredBoards = value);

      sort = sortBy;
    });
  }

  Widget getBoardView(List<Post> threads) {
    return BoardGridView(
      scrollController: scrollController,
      board: widget.board,
      threads: threads,
    );
  }

  void _updateThreadsList(String value) {
    _fetchAllThreadsFromBoard = fetchAllThreadsFromBoard(
      sort,
      widget.board,
      searchValue: value,
    ).then((value) => filteredBoards = value);

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeChanger>(context);
    final settings = Provider.of<SettingsProvider>(context);
    final bool isDark = theme.getTheme() == ThemeData.dark();

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: CupertinoPageScaffold(
        backgroundColor: AppColors.pageBackground(isDark),
        child: Scrollbar(
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              CupertinoSliverNavigationBar(
                backgroundColor: AppColors.navigationBackground(isDark),
                largeTitle: MediaQuery(
                  data: MediaQueryData(
                    textScaler: TextScaler.linear(
                      MediaQuery.textScaleFactorOf(context),
                    ),
                  ),
                  child: Text(
                    '/${widget.board}/ - ${widget.boardName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.getTheme() == ThemeData.dark()
                          ? CupertinoColors.white
                          : CupertinoColors.black,
                    ),
                  ),
                ),
                leading: MediaQuery(
                  data: MediaQueryData(
                    textScaler: TextScaler.linear(
                      MediaQuery.textScaleFactorOf(context),
                    ),
                  ),
                  child: Transform.translate(
                    offset: const Offset(-16, 0),
                    child: CupertinoNavigationBarBackButton(
                      previousPageTitle: 'Home',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FavoriteButton(board: widget.board),
                    SizedBox(
                      width: 20,
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          showCupertinoModalPopup(
                            context: context,
                            builder: (BuildContext context) =>
                                CupertinoActionSheet(
                                  message: const Text('Sort by'),
                                  actions: [
                                    CupertinoActionSheetAction(
                                      child: Text(
                                        'Image Count',
                                        style: sort == Sort.byImagesCount
                                            ? const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              )
                                            : const TextStyle(
                                                fontWeight: FontWeight.normal,
                                              ),
                                      ),
                                      onPressed: () {
                                        setSort(Sort.byImagesCount, settings);
                                        Navigator.pop(context);
                                      },
                                    ),
                                    CupertinoActionSheetAction(
                                      child: Text(
                                        'Reply Count',
                                        style: sort == Sort.byReplyCount
                                            ? const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              )
                                            : const TextStyle(
                                                fontWeight: FontWeight.normal,
                                              ),
                                      ),
                                      onPressed: () {
                                        setSort(Sort.byReplyCount, settings);
                                        Navigator.pop(context);
                                      },
                                    ),
                                    CupertinoActionSheetAction(
                                      child: Text(
                                        'Bump Order',
                                        style: sort == Sort.byBumpOrder
                                            ? const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              )
                                            : const TextStyle(
                                                fontWeight: FontWeight.normal,
                                              ),
                                      ),
                                      onPressed: () {
                                        setSort(Sort.byBumpOrder, settings);
                                        Navigator.pop(context);
                                      },
                                    ),
                                    CupertinoActionSheetAction(
                                      child: Text(
                                        'Newest',
                                        style: sort == Sort.byNewest
                                            ? const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              )
                                            : const TextStyle(
                                                fontWeight: FontWeight.normal,
                                              ),
                                      ),
                                      onPressed: () {
                                        setSort(Sort.byNewest, settings);
                                        Navigator.pop(context);
                                      },
                                    ),
                                    CupertinoActionSheetAction(
                                      child: Text(
                                        'Oldest',
                                        style: sort == Sort.byOldest
                                            ? const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              )
                                            : const TextStyle(
                                                fontWeight: FontWeight.normal,
                                              ),
                                      ),
                                      onPressed: () {
                                        setSort(Sort.byOldest, settings);
                                        Navigator.pop(context);
                                      },
                                    ),
                                  ],
                                  cancelButton: CupertinoActionSheetAction(
                                    child: const Text('Cancel'),
                                    onPressed: () {
                                      Navigator.pop(context);
                                    },
                                  ),
                                ),
                          );
                        },
                        child: const Icon(Icons.sort),
                      ),
                    ),
                  ],
                ),
                border: null,
                stretch: true,
              ),
              SliverList(
                delegate: SliverChildListDelegate([
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: 10,
                      left: 10,
                      right: 10,
                    ),
                    child: ClipRect(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.getTheme() == ThemeData.light()
                              ? Colors.white
                              : const Color(0xFF13161B),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: theme.getTheme() == ThemeData.light()
                              ? const [
                                  BoxShadow(
                                    color: Color(0x12000000),
                                    blurRadius: 10,
                                    offset: Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: CupertinoSearchTextField(
                          controller: _searchBarController,
                          backgroundColor: Colors.transparent,
                          onChanged: (value) {
                            _updateThreadsList(value);
                          },
                          onSubmitted: (value) {
                            _updateThreadsList(value);
                          },
                          onSuffixTap: () {
                            _updateThreadsList('');
                            _searchBarController.clear();
                          },
                        ),
                      ),
                    ),
                  ),
                  FutureBuilder(
                    future: _fetchAllThreadsFromBoard,
                    builder:
                        (
                          BuildContext context,
                          AsyncSnapshot<List<Post>> snapshot,
                        ) {
                          switch (snapshot.connectionState) {
                            case ConnectionState.waiting:
                              return const SizedBox(
                                height: 400,
                                child: Center(
                                  child: CupertinoActivityIndicator(),
                                ),
                              );
                            default:
                              if (snapshot.hasError) {
                                return ReloadWidget(
                                  onReload: () => {loadBoard()},
                                );
                              } else {
                                return getBoardView(filteredBoards);
                              }
                          }
                        },
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
