import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/Models/board.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/favorite_model.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/pages/boards/board_tile.dart';
import 'package:flutter_chan/pages/bookmarks/bookmarks.dart';
import 'package:flutter_chan/pages/savedAttachments/saved_attachments.dart';
import 'package:flutter_chan/pages/thread/thread_page.dart';
import 'package:flutter_chan/widgets/reload.dart';
import 'package:provider/provider.dart';

import '../settings/settings.dart';

class BoardList extends StatefulWidget {
  const BoardList({Key? key}) : super(key: key);

  @override
  BoardListState createState() => BoardListState();
}

class BoardListState extends State<BoardList> {
  late Future<List<Board>> _fetchAllBoards;
  TextEditingController controller = TextEditingController();
  final TextEditingController _searchBarController = TextEditingController();

  bool showWarning = false;
  String warningText = 'This link is not supported';

  late List<Board> filterdBoards;

  @override
  void initState() {
    super.initState();

    loadBoards();
  }

  void loadBoards() {
    setState(() {
      _fetchAllBoards = fetchAllBoards().then((value) => filterdBoards = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeChanger>(context);
    final favorites = Provider.of<FavoriteProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);

    Future<bool> openURL() async {
      if (controller.text.isEmpty) {
        showWarning = true;

        setState(() {
          warningText = 'Please enter a link';
        });

        return true;
      }

      try {
        controller.text = controller.text.trim();
        final regExDomains = RegExp(
          r'^(?:https?:\/\/)?(?:[^@\n]+@)?(?:www.)?([^:\/\n?]+)',
        );
        final matchDomain = regExDomains.firstMatch(controller.text);
        final domain = matchDomain?.group(1);

        if (domain == 'boards.4chan.org' || domain == 'boards.4channel.org') {
          final regEx = RegExp(r'^https?:\/\/[A-Za-z0-9:.]*([\/]{1}.*\/?)$');
          final match = regEx.firstMatch(controller.text);
          final removedFirst = match?.group(1)?.replaceFirst('/', '');
          final splitted = removedFirst?.split('/');

          List<Post> response;

          try {
            response = await fetchAllPostsFromThread(
              splitted!.first,
              int.parse(splitted.last),
            );
          } catch (e) {
            showWarning = true;
            warningText = e.toString();
            return true;
          }

          controller.clear();

          Navigator.of(context).pop();

          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ThreadPage(
                post: response[0],
                threadName: response[0].sub ?? response[0].com ?? 'No Title',
                thread: response[0].no ?? 0,
                board: splitted.first,
              ),
            ),
          );

          return false;
        } else {
          warningText = 'This link is not supported';
          return true;
        }
      } catch (e) {
        showWarning = true;
        warningText = e.toString();
        return true;
      }
    }

    void _updateUserList(String value, List<Board>? data) {
      if (data == null) {
        return;
      }

      if (value.isNotEmpty) {
        filterdBoards = data
            .where(
              (element) =>
                  element.board!.toLowerCase().contains(value.toLowerCase()) ||
                  element.metaDescription!.toLowerCase().contains(
                    value.toLowerCase(),
                  ) ||
                  element.metaDescription!.toLowerCase().contains(
                    value.toLowerCase(),
                  ) ||
                  element.title!.toLowerCase().contains(value.toLowerCase()),
            )
            .toList();
      } else {
        _searchBarController.clear();
        filterdBoards = data;
      }

      setState(() {});
    }

    return CupertinoPageScaffold(
      backgroundColor: theme.getTheme() == ThemeData.light()
          ? CupertinoColors.systemGroupedBackground
          : Colors.black,
      child: Scrollbar(
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            CupertinoSliverNavigationBar(
              backgroundColor: theme.getTheme() == ThemeData.light()
                  ? CupertinoColors.systemGroupedBackground.withValues(
                      alpha: 0.7,
                    )
                  : CupertinoColors.black.withOpacity(0.7),
              largeTitle: MediaQuery(
                data: MediaQueryData(
                  textScaler: TextScaler.linear(
                    MediaQuery.textScaleFactorOf(context),
                  ),
                ),
                child: Text(
                  'NekoSurf',
                  style: TextStyle(
                    color: theme.getTheme() == ThemeData.dark()
                        ? CupertinoColors.white
                        : CupertinoColors.black,
                  ),
                ),
              ),
              leading: CupertinoButton(
                padding: EdgeInsets.zero,
                child: MediaQuery(
                  data: MediaQueryData(
                    textScaler: TextScaler.linear(
                      MediaQuery.textScaleFactorOf(context),
                    ),
                  ),
                  child: const Text(
                    'Open Link',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
                onPressed: () => {
                  showWarning = false,
                  showCupertinoDialog(
                    barrierDismissible: true,
                    context: context,
                    builder: (context) {
                      return StatefulBuilder(
                        builder: (context, setState) {
                          return CupertinoAlertDialog(
                            title: const Text('Open Link'),
                            content: Column(
                              children: [
                                const SizedBox(height: 10),
                                Visibility(
                                  visible: showWarning,
                                  child: Column(
                                    children: [
                                      Text(
                                        warningText,
                                        style: const TextStyle(
                                          color: Colors.red,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                    ],
                                  ),
                                ),
                                Card(
                                  color: Colors.transparent,
                                  elevation: 0.0,
                                  child: Column(
                                    children: [
                                      CupertinoTextField(
                                        controller: controller,
                                        placeholder: 'Insert Thread URL',
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            actions: [
                              CupertinoDialogAction(
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: CupertinoColors.activeBlue,
                                  ),
                                ),
                                onPressed: () => {
                                  controller.clear(),
                                  Navigator.pop(context),
                                },
                              ),
                              CupertinoDialogAction(
                                child: const Text(
                                  'Open',
                                  style: TextStyle(
                                    color: CupertinoColors.activeBlue,
                                  ),
                                ),
                                onPressed: () => {
                                  openURL().then(
                                    (value) => {
                                      if (value)
                                        {
                                          setState(() {
                                            showWarning = true;
                                          }),
                                        },
                                    },
                                  ),
                                },
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                },
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const SavedAttachments(),
                        ),
                      );
                    },
                    child: const Icon(CupertinoIcons.bookmark),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const Bookmarks(),
                        ),
                      );
                    },
                    child: const Icon(CupertinoIcons.heart),
                  ),
                  SizedBox(
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const Settings(),
                          ),
                        );
                      },
                      child: const Icon(CupertinoIcons.settings),
                    ),
                  ),
                ],
              ),
              border: null,
              stretch: true,
            ),
            SliverList(
              delegate: SliverChildListDelegate([
                FutureBuilder(
                  future: _fetchAllBoards,
                  builder:
                      (
                        BuildContext context,
                        AsyncSnapshot<List<Board>> snapshot,
                      ) {
                        switch (snapshot.connectionState) {
                          case ConnectionState.waiting:
                            return const Column(
                              children: [
                                SizedBox(height: 100),
                                CupertinoActivityIndicator(),
                              ],
                            );
                          default:
                            if (snapshot.hasError) {
                              return ReloadWidget(onReload: () => loadBoards());
                            } else {
                              return Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: 8.0,
                                      left: 16.0,
                                      right: 16.0,
                                    ),
                                    child: ClipRect(
                                      child: CupertinoSearchTextField(
                                        controller: _searchBarController,
                                        onChanged: (value) {
                                          _updateUserList(value, snapshot.data);
                                        },
                                        onSubmitted: (value) {
                                          _updateUserList(value, snapshot.data);
                                        },
                                        onSuffixTap: () {
                                          _updateUserList('', snapshot.data);
                                        },
                                      ),
                                    ),
                                  ),
                                  if (favorites.getFavorites().isNotEmpty)
                                    CupertinoListSection.insetGrouped(
                                      header: Text(
                                        'Favorites',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color:
                                              theme.getTheme() ==
                                                  ThemeData.dark()
                                              ? CupertinoColors.white
                                              : CupertinoColors.black,
                                        ),
                                      ),
                                      children: [
                                        for (final Board board in filterdBoards)
                                          if (favorites.getFavorites().contains(
                                            board.board,
                                          ))
                                            if (settings.getNSFW())
                                              BoardTile(
                                                board: board,
                                                favorites: favorites
                                                    .getFavorites()
                                                    .contains(board.board),
                                              )
                                            else if (board.wsBoard != 0)
                                              BoardTile(
                                                board: board,
                                                favorites: favorites
                                                    .getFavorites()
                                                    .contains(board.board),
                                              ),
                                      ],
                                    ),
                                  CupertinoListSection.insetGrouped(
                                    header: Text(
                                      'Boards',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color:
                                            theme.getTheme() == ThemeData.dark()
                                            ? CupertinoColors.white
                                            : CupertinoColors.black,
                                      ),
                                    ),
                                    children: [
                                      for (final Board board in filterdBoards)
                                        if (settings.getNSFW())
                                          BoardTile(
                                            board: board,
                                            favorites: favorites
                                                .getFavorites()
                                                .contains(board.board),
                                          )
                                        else if (board.wsBoard != 0)
                                          BoardTile(
                                            board: board,
                                            favorites: favorites
                                                .getFavorites()
                                                .contains(board.board),
                                          ),
                                    ],
                                  ),
                                ],
                              );
                            }
                        }
                      },
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
