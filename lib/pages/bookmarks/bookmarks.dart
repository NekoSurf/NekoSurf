import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/favorite.dart';
import 'package:flutter_chan/blocs/bookmarks_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_chan/pages/bookmarks/bookmarks_post.dart';
import 'package:provider/provider.dart';

class Bookmarks extends StatefulWidget {
  const Bookmarks({Key? key}) : super(key: key);

  @override
  State<Bookmarks> createState() => _BookmarksState();
}

class _BookmarksState extends State<Bookmarks> {
  final ScrollController scrollController = ScrollController();

  Future<Iterable<String>> getBookmarks() {
    final bookmarks = Provider.of<BookmarksProvider>(context, listen: false);

    return Future.value(bookmarks.getBookmarks());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeChanger>(context);
    final bookmarks = Provider.of<BookmarksProvider>(context);

    return Scaffold(
      body: CupertinoPageScaffold(
        backgroundColor: theme.getTheme() == ThemeData.light()
            ? CupertinoColors.systemGroupedBackground
            : CupertinoColors.black,
        child: Scrollbar(
          child: CustomScrollView(
            slivers: [
              CupertinoSliverNavigationBar(
                leading: MediaQuery(
                  data: MediaQueryData(
                    textScaleFactor: MediaQuery.textScaleFactorOf(context),
                  ),
                  child: Transform.translate(
                    offset: const Offset(-16, 0),
                    child: CupertinoNavigationBarBackButton(
                      previousPageTitle: 'Home',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
                previousPageTitle: 'Home',
                border: Border.all(color: Colors.transparent),
                largeTitle: MediaQuery(
                  data: MediaQueryData(
                    textScaleFactor: MediaQuery.textScaleFactorOf(context),
                  ),
                  child: Text(
                    'Bookmarks',
                    style: TextStyle(
                      color: theme.getTheme() == ThemeData.dark()
                          ? CupertinoColors.white
                          : CupertinoColors.black,
                    ),
                  ),
                ),
                backgroundColor: theme.getTheme() == ThemeData.light()
                    ? CupertinoColors.systemGroupedBackground.withOpacity(0.7)
                    : CupertinoColors.black.withOpacity(0.7),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        showCupertinoModalPopup(
                          context: context,
                          builder: (BuildContext context) =>
                              CupertinoActionSheet(
                            message: const Text(
                              'Sort by',
                            ),
                            actions: [
                              CupertinoActionSheetAction(
                                child: const Text('Newest'),
                                onPressed: () {
                                  bookmarks.setSort(Sort.byNewest);
                                  Navigator.pop(context);
                                },
                              ),
                              CupertinoActionSheetAction(
                                child: const Text('Oldest'),
                                onPressed: () {
                                  bookmarks.setSort(Sort.byOldest);
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
                    SizedBox(
                      width: 20,
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          showCupertinoModalPopup(
                            context: context,
                            builder: (BuildContext context) =>
                                CupertinoActionSheet(
                              actions: [
                                CupertinoActionSheetAction(
                                  child: const Text('Clear bookmarks'),
                                  onPressed: () {
                                    bookmarks.clearBookmarks();
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
                        child: const Icon(Icons.more_vert),
                      ),
                    ),
                  ],
                ),
              ),
              SliverList(
                delegate: SliverChildListDelegate(
                  [
                    if (bookmarks.getBookmarks().isEmpty)
                      Column(
                        children: [
                          const SizedBox(
                            height: 30,
                          ),
                          Text(
                            'Add bookmarks first!',
                            style: TextStyle(
                              fontSize: 26,
                              color: theme.getTheme() == ThemeData.dark()
                                  ? Colors.white
                                  : Colors.black,
                            ),
                          ),
                        ],
                      )
                    else
                      Column(
                        children: [
                          FutureBuilder<Iterable<String>>(
                              future: getBookmarks(),
                              builder: (BuildContext context,
                                  AsyncSnapshot<Iterable<String>> snapshot) {
                                switch (snapshot.connectionState) {
                                  case ConnectionState.waiting:
                                    return Container();
                                  default:
                                    return Column(
                                      children: [
                                        for (final String string
                                            in snapshot.data ?? <String>[])
                                          BookmarksPost(
                                            favorite: Favorite.fromJson(
                                              json.decode(string)
                                                  as Map<String, dynamic>,
                                            ),
                                          )
                                      ],
                                    );
                                }
                              }),
                        ],
                      ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
