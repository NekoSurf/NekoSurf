import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/Models/board.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/bookmarks_model.dart';
import 'package:flutter_chan/blocs/favorite_model.dart';
import 'package:flutter_chan/blocs/saved_attachments_model.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/constants.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_chan/pages/boards/board_list_header.dart';
import 'package:flutter_chan/pages/boards/board_tile.dart';
import 'package:flutter_chan/pages/bookmarks/bookmarks.dart';
import 'package:flutter_chan/pages/feed/feed_page.dart';
import 'package:flutter_chan/pages/savedAttachments/saved_attachments.dart';
import 'package:flutter_chan/pages/settings/settings.dart';
import 'package:flutter_chan/pages/thread/thread_page.dart';
import 'package:flutter_chan/services/update_checker.dart';
import 'package:flutter_chan/widgets/cupertino_menu.dart';
import 'package:flutter_chan/widgets/reload.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:liquid_glass_widgets/types/glass_quality.dart';
import 'package:liquid_glass_widgets/widgets/surfaces/glass_scaffold.dart';
import 'package:liquid_glass_widgets/widgets/surfaces/glass_tab_bar.dart';
import 'package:provider/provider.dart';

class BoardList extends StatefulWidget {
  const BoardList({Key? key}) : super(key: key);

  @override
  BoardListState createState() => BoardListState();
}

class BoardListState extends State<BoardList> {
  late Future<List<Board>> _fetchAllBoards;
  TextEditingController controller = TextEditingController();
  final TextEditingController _searchBarController = TextEditingController();

  final _titleController = GlassLargeTitleController();

  int currentIndex = 0;

  @override
  void dispose() {
    _searchBarController.dispose();
    _titleController.dispose();
    controller.dispose();
    super.dispose();
  }

  bool showWarning = false;
  String warningText = 'This link is not supported';

  late List<Board> filteredBoards;

  @override
  void initState() {
    super.initState();

    loadBoards();
    if (Platform.isAndroid || Platform.isIOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
    }
  }

  Future<void> _checkForUpdates() async {
    final updateUrl = await checkForAppUpdate();
    if (!mounted || updateUrl == null) {
      return;
    }

    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Update available'),
        content: Text(
          Platform.isIOS
              ? 'A newer version of NekoSurf is available on TestFlight.'
              : 'A newer version of NekoSurf is available.',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Later'),
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: Text(Platform.isIOS ? 'Open TestFlight' : 'View release'),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              launchURL(updateUrl.toString());
            },
          ),
        ],
      ),
    );
  }

  void loadBoards() {
    setState(() {
      _fetchAllBoards = fetchAllBoards().then(
        (value) => filteredBoards = value,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeChanger>(context);
    final favorites = Provider.of<FavoriteProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);
    final bool isDark = theme.getTheme() == ThemeData.dark();

    Future<bool> openURL(StateSetter setDialogState) async {
      if (controller.text.isEmpty) {
        setDialogState(() {
          showWarning = true;
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
            setDialogState(() {
              showWarning = true;
              warningText = e.toString();
            });
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
          setDialogState(() {
            showWarning = true;
            warningText = 'This link is not supported';
          });
          return true;
        }
      } catch (e) {
        setDialogState(() {
          showWarning = true;
          warningText = e.toString();
        });
        return true;
      }
    }

    void _updateBoardList(String value, List<Board>? data) {
      if (data == null) {
        return;
      }

      if (value.isNotEmpty) {
        filteredBoards = data
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
        filteredBoards = data;
      }

      setState(() {});
    }

    String buildTitle() {
      if (currentIndex == 0) {
        return 'NekoSurf';
      } else if (currentIndex == 1) {
        return 'Saved Attachments';
      } else if (currentIndex == 2) {
        return 'Bookmarks';
      } else if (currentIndex == 3) {
        return 'Settings';
      }

      return 'NekoSurf';
    }

    Widget buildPageContent() {
      return CustomScrollView(
        controller: _titleController.scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.paddingOf(context).top + 52),
          ),

          GlassLargeTitle(
            text: buildTitle(),
            controller: _titleController,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          ),

          if (currentIndex == 0)
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
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20.0,
                                      vertical: 8.0,
                                    ),
                                    child: CupertinoSearchTextField(
                                      controller: _searchBarController,
                                      onChanged: (value) {
                                        _updateBoardList(value, snapshot.data);
                                      },
                                    ),
                                  ),

                                  if (favorites.getFavorites().isNotEmpty)
                                    CupertinoListSection.insetGrouped(
                                      backgroundColor: Colors.transparent,
                                      header: BoardListHeader(
                                        title: 'Favorites',
                                        icon: CupertinoIcons.heart_fill,
                                        iconColor: CupertinoColors.systemPink,
                                        isDark: isDark,
                                      ),
                                      children: [
                                        CupertinoListTile.notched(
                                          leading: const Icon(
                                            CupertinoIcons.rectangle_stack_fill,
                                            color: CupertinoColors.systemPink,
                                          ),
                                          title: const Text(
                                            'Feed',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          subtitle: const Text(
                                            'Threads from all favorite boards',
                                          ),
                                          trailing:
                                              const CupertinoListTileChevron(),
                                          onTap: () =>
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (context) =>
                                                      const FeedPage(),
                                                ),
                                              ),
                                        ),
                                        for (final Board board
                                            in filteredBoards)
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
                                    backgroundColor: Colors.transparent,
                                    header: BoardListHeader(
                                      title: 'Boards',
                                      icon: CupertinoIcons.square_grid_2x2_fill,
                                      iconColor: CupertinoColors.activeBlue,
                                      isDark: isDark,
                                    ),
                                    children: [
                                      for (final Board board in filteredBoards)
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

          if (currentIndex == 1) const SavedAttachments(),
          if (currentIndex == 2) const Bookmarks(),
          if (currentIndex == 3) const Settings(),

          SliverToBoxAdapter(
            child: SizedBox(
              height: MediaQuery.paddingOf(context).bottom + 50 + 8,
            ),
          ),
        ],
      );
    }

    List<Widget> buildActions() {
      final savedAttachments = Provider.of<SavedAttachmentsProvider>(context);
      final bookmarks = Provider.of<BookmarksProvider>(context);

      if (currentIndex == 0) {
        return [
          GlassIconButton(
            icon: const Icon(CupertinoIcons.link),
            onPressed: () {
              showWarning = false;

              showCupertinoDialog<void>(
                context: context,
                barrierDismissible: true,
                builder: (context) => StatefulBuilder(
                  builder: (context, setDialogState) {
                    return CupertinoAlertDialog(
                      title: const Text('Open Link'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 10),
                          Visibility(
                            visible: showWarning,
                            child: Column(
                              children: [
                                Text(
                                  warningText,
                                  style: const TextStyle(
                                    color: CupertinoColors.systemRed,
                                  ),
                                ),
                                const SizedBox(height: 5),
                              ],
                            ),
                          ),
                          CupertinoTextField(
                            controller: controller,
                            placeholder: 'Insert Thread URL',
                          ),
                        ],
                      ),
                      actions: [
                        CupertinoDialogAction(
                          child: const Text('Cancel'),
                          onPressed: () => Navigator.pop(context),
                        ),
                        CupertinoDialogAction(
                          isDefaultAction: true,
                          child: const Text('Open'),
                          onPressed: () => openURL(setDialogState),
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ];
      } else if (currentIndex == 1) {
        return [
          CupertinoMenuButton(
            glassIcon: const Icon(CupertinoIcons.ellipsis_circle),
            isGlass: true,
            menuChildren: [
              buildMenuItem(
                title: 'Clear attachments',
                icon: CupertinoIcons.trash,
                isDestructive: true,
                onPressed: () =>
                    savedAttachments.clearSavedAttachments(context),
              ),
            ],
          ),
        ];
      } else if (currentIndex == 2) {
        return [
          CupertinoMenuButton(
            glassIcon: const Icon(CupertinoIcons.sort_down),
            isGlass: true,
            icon: CupertinoIcons.sort_down,
            menuChildren: [
              buildMenuItem(
                title: 'Newest',
                icon: CupertinoIcons.clock,
                onPressed: () => bookmarks.setSort(Sort.byNewest),
              ),
              buildMenuItem(
                title: 'Oldest',
                icon: CupertinoIcons.clock_fill,
                onPressed: () => bookmarks.setSort(Sort.byOldest),
              ),
            ],
          ),
          CupertinoMenuButton(
            glassIcon: const Icon(CupertinoIcons.ellipsis_circle),
            isGlass: true,
            icon: CupertinoIcons.ellipsis_circle,
            menuChildren: [
              buildMenuItem(
                title: 'Clear bookmarks',
                icon: CupertinoIcons.trash,
                isDestructive: true,
                onPressed: () => bookmarks.clearBookmarks(),
              ),
            ],
          ),
        ];
      } else {
        return [];
      }
    }

    return GlassScaffold(
      backgroundColor: AppColors.pageBackground(
        Theme.of(context).brightness == Brightness.dark,
      ),
      appBar: GlassAppBar(
        toolbarHeight: 52,
        title: Text(
          buildTitle(),
          style: TextStyle(
            color: CupertinoColors.label.resolveFrom(context),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        largeTitleController: _titleController,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        actions: buildActions(),
      ),
      bottomBar: GlassTabBar.bottom(
        settings: LiquidGlassSettings(
          glassColor: CupertinoTheme.of(context).brightness == Brightness.dark
              ? const Color(0xAA1C1C1E)
              : const Color(0xAAF2F2F7),
          thickness: 30,
          blur: 2,
          chromaticAberration: .01,
          lightAngle: GlassDefaults.lightAngle,
          lightIntensity: 0.2,
          ambientStrength: 0,
          refractiveIndex: 1.2,
          fresnelStrength: 0.0,
          saturation: 1.2,
          specularSharpness: GlassSpecularSharpness.medium,
        ),
        quality: GlassQuality.premium,
        tabs: const [
          GlassTab(
            icon: Icon(CupertinoIcons.square_grid_2x2_fill),
            label: 'Boards',
          ),
          GlassTab(icon: Icon(CupertinoIcons.paperclip), label: 'Attachments'),
          GlassTab(
            icon: Icon(CupertinoIcons.bookmark_fill),
            label: 'Bookmarks',
          ),
          GlassTab(icon: Icon(CupertinoIcons.settings), label: 'Settings'),
        ],
        selectedIndex: currentIndex,
        onTabSelected: (i) => setState(() => currentIndex = i),
      ),
      body: buildPageContent(),
    );
  }
}
