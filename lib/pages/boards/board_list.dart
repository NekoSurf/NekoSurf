import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/API/save_videos.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/bookmarks_model.dart';
import 'package:flutter_chan/blocs/saved_attachments_model.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_chan/pages/bookmarks/bookmarks.dart';
import 'package:flutter_chan/pages/dashboard/dashboard.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:flutter_chan/pages/savedAttachments/saved_attachments.dart';
import 'package:flutter_chan/pages/settings/settings.dart';
import 'package:flutter_chan/pages/thread/thread_page.dart';
import 'package:flutter_chan/services/show_snackbar.dart';
import 'package:flutter_chan/services/update_checker.dart';
import 'package:flutter_chan/widgets/cupertino_menu.dart';
import 'package:flutter_chan/widgets/dash_dialogs.dart';
import 'package:flutter_chan/widgets/dash_header.dart';
import 'package:flutter_chan/widgets/dash_scaffold.dart';
import 'package:provider/provider.dart';

class BoardList extends StatefulWidget {
  const BoardList({Key? key}) : super(key: key);

  @override
  BoardListState createState() => BoardListState();
}

class BoardListState extends State<BoardList> {
  TextEditingController controller = TextEditingController();

  final _dashboardKey = GlobalKey<DashboardState>();

  int currentIndex = 0;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  bool showWarning = false;
  String warningText = 'This link is not supported';

  @override
  void initState() {
    super.initState();

    if (Platform.isAndroid || Platform.isIOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
    }
  }

  Future<void> _checkForUpdates() async {
    final updateUrl = await checkForAppUpdate();
    if (!mounted || updateUrl == null) {
      return;
    }

    await showDashDialog<void>(
      context: context,
      builder: (dialogContext) => DashDialog(
        title: const Text('Update available'),
        content: Text(
          Platform.isIOS
              ? 'A newer version of NekoSurf is available on TestFlight.'
              : 'A newer version of NekoSurf is available.',
        ),
        actions: [
          DashDialogAction(
            child: const Text('Later'),
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          DashDialogAction(
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

  Future<bool> _openURL(StateSetter setDialogState) async {
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

  void showOpenLinkDialog() {
    showWarning = false;

    showDashDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return DashDialog(
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
                        style: const TextStyle(color: DashColors.nsfw),
                      ),
                      const SizedBox(height: 5),
                    ],
                  ),
                ),
                CupertinoTextField(
                  controller: controller,
                  placeholder: 'Insert Thread URL',
                  padding: const EdgeInsets.all(14),
                  style: TextStyle(
                    color: DashColors.text(
                      CupertinoTheme.brightnessOf(context) == Brightness.dark,
                    ),
                  ),
                  decoration: BoxDecoration(
                    color: DashColors.muted(
                      CupertinoTheme.brightnessOf(context) == Brightness.dark,
                    ).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ],
            ),
            actions: [
              DashDialogAction(
                child: const Text('Cancel'),
                onPressed: () => Navigator.pop(context),
              ),
              DashDialogAction(
                isDefaultAction: true,
                child: const Text('Open'),
                onPressed: () => _openURL(setDialogState),
              ),
            ],
          );
        },
      ),
    );
  }

  void _selectTab(int i) {
    if (currentIndex == 1 && i != 1) {
      Provider.of<SavedAttachmentsProvider>(
        context,
        listen: false,
      ).setSelecting(false);
    }
    setState(() => currentIndex = i);
  }

  @override
  Widget build(BuildContext context) {
    String buildTitle() {
      if (currentIndex == 0) {
        return 'NekoSurf';
      } else if (currentIndex == 1) {
        final saved = Provider.of<SavedAttachmentsProvider>(context);
        if (saved.selecting) {
          return saved.selected.isEmpty
              ? 'Select Items'
              : '${saved.selected.length} Selected';
        }
        return 'Saved Attachments';
      } else if (currentIndex == 2) {
        return 'Bookmarks';
      } else if (currentIndex == 3) {
        return 'Settings';
      }

      return 'NekoSurf';
    }

    List<Widget> buildSlivers() {
      return [
        if (currentIndex == 0)
          Dashboard(key: _dashboardKey, onSelectTab: _selectTab),
        if (currentIndex == 1) const SavedAttachments(),
        if (currentIndex == 2) const Bookmarks(),
        if (currentIndex == 3) const Settings(),
      ];
    }

    List<Widget> buildActions() {
      final savedAttachments = Provider.of<SavedAttachmentsProvider>(context);
      final bookmarks = Provider.of<BookmarksProvider>(context);

      if (currentIndex == 0) {
        return [
          DashIconButton(
            icon: const Icon(CupertinoIcons.link),
            onPressed: showOpenLinkDialog,
          ),
        ];
      } else if (currentIndex == 1) {
        if (savedAttachments.selecting) {
          final bool hasSelection = savedAttachments.selected.isNotEmpty;
          return [
            DashIconButton(
              icon: const Icon(CupertinoIcons.arrow_down_to_line),
              onPressed: hasSelection
                  ? () async {
                      final names = savedAttachments.selected.toList();
                      final failed = await saveSavedAttachmentsToGallery(
                        names,
                        context,
                      );
                      if (!mounted) {
                        return;
                      }
                      showCupertinoSnackbar(
                        const Duration(milliseconds: 2200),
                        failed > 0,
                        context,
                        failed == 0
                            ? 'Saved ${names.length} to Photos'
                            : '$failed of ${names.length} failed to save',
                      );
                    }
                  : () {},
            ),
            DashIconButton(
              icon: const Icon(CupertinoIcons.share),
              onPressed: hasSelection
                  ? () => shareSavedAttachments(
                      savedAttachments.selected.toList(),
                      context,
                    )
                  : () {},
            ),
            DashIconButton(
              icon: const Icon(CupertinoIcons.trash, color: Color(0xFFFF5D6C)),
              onPressed: hasSelection
                  ? () => showDashDialog<void>(
                      context: context,
                      builder: (dialogContext) => DashDialog(
                        title: Text(
                          'Delete ${savedAttachments.selected.length} items?',
                        ),
                        content: const Text(
                          'They will be removed from your saved attachments.',
                        ),
                        actions: [
                          DashDialogAction(
                            child: const Text('Cancel'),
                            onPressed: () => Navigator.of(dialogContext).pop(),
                          ),
                          DashDialogAction(
                            isDestructiveAction: true,
                            child: const Text('Delete'),
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                              savedAttachments.removeSelected(context);
                            },
                          ),
                        ],
                      ),
                    )
                  : () {},
            ),
            CupertinoMenuButton(
              glassIcon: const Icon(CupertinoIcons.ellipsis_circle),
              isGlass: true,
              menuChildren: [
                buildMenuItem(
                  title: 'Select all',
                  icon: CupertinoIcons.checkmark_circle_fill,
                  onPressed: savedAttachments.selectAll,
                ),
                buildMenuItem(
                  title: 'Deselect all',
                  icon: CupertinoIcons.circle,
                  onPressed: savedAttachments.deselectAll,
                ),
              ],
            ),
            DashIconButton(
              icon: const Icon(CupertinoIcons.xmark),
              onPressed: () => savedAttachments.setSelecting(false),
            ),
          ];
        }
        return [
          CupertinoMenuButton(
            glassIcon: const Icon(CupertinoIcons.ellipsis_circle),
            isGlass: true,
            menuChildren: [
              buildMenuItem(
                title: 'Select',
                icon: CupertinoIcons.checkmark_circle,
                onPressed: () => savedAttachments.setSelecting(true),
              ),
              const DashMenuDivider(),
              buildMenuItem(
                title: 'Newest first',
                icon: CupertinoIcons.arrow_down,
                isSelected: savedAttachments.newestFirst,
                onPressed: () => savedAttachments.setNewestFirst(true),
              ),
              buildMenuItem(
                title: 'Oldest first',
                icon: CupertinoIcons.arrow_up,
                isSelected: !savedAttachments.newestFirst,
                onPressed: () => savedAttachments.setNewestFirst(false),
              ),
              const DashMenuDivider(),
              buildMenuItem(
                title: 'Clear attachments',
                icon: CupertinoIcons.trash,
                isDestructive: true,
                onPressed: () => showDashDialog<void>(
                  context: context,
                  builder: (dialogContext) => DashDialog(
                    title: const Text('Clear all attachments?'),
                    content: const Text(
                      'This permanently deletes all saved attachments from the app.',
                    ),
                    actions: [
                      DashDialogAction(
                        isDefaultAction: true,
                        child: const Text('Cancel'),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                      DashDialogAction(
                        isDestructiveAction: true,
                        child: const Text('Clear'),
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          savedAttachments.clearSavedAttachments(context);
                        },
                      ),
                    ],
                  ),
                ),
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

    return DashScaffold(
      title: buildTitle(),
      subtitle: currentIndex == 0 ? 'Browse the boards' : null,
      leading: currentIndex == 0
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/icons/icon-round.png',
                width: 38,
                height: 38,
              ),
            )
          : null,
      actions: buildActions(),
      keyboardDismiss: true,
      onRefresh: currentIndex == 0
          ? () async => _dashboardKey.currentState?.refresh()
          : null,
      slivers: buildSlivers(),
      bottomBar: DashTabBar(
        selectedIndex: currentIndex,
        onSelected: _selectTab,
        tabs: const [
          DashTab(CupertinoIcons.square_grid_2x2_fill, 'Boards'),
          DashTab(CupertinoIcons.paperclip, 'Saved'),
          DashTab(CupertinoIcons.bookmark_fill, 'Bookmarks'),
          DashTab(CupertinoIcons.settings, 'Settings'),
        ],
      ),
    );
  }
}
