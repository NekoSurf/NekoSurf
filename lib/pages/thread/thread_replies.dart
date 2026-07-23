import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/constants.dart';
import 'package:flutter_chan/pages/thread/thread_page_post.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/widgets/interactive/glass_button.dart';
import 'package:liquid_glass_widgets/widgets/surfaces/glass_app_bar.dart';
import 'package:liquid_glass_widgets/widgets/surfaces/glass_scaffold.dart';

class _ReplyTreeEntry {
  const _ReplyTreeEntry({
    required this.post,
    required this.branchState,
    required this.hasChildren,
    required this.hiddenReplyCount,
    required this.isCollapsed,
  });

  final Post post;
  final List<bool> branchState;
  final bool hasChildren;
  final int hiddenReplyCount;
  final bool isCollapsed;
}

class ThreadReplies extends ConsumerStatefulWidget {
  const ThreadReplies({
    Key? key,
    required this.post,
    required this.thread,
    required this.board,
    required this.allPosts,
  }) : super(key: key);

  final Post post;
  final int thread;
  final String board;
  final List<Post> allPosts;

  @override
  ConsumerState<ThreadReplies> createState() => _ThreadRepliesState();
}

class _ThreadRepliesState extends ConsumerState<ThreadReplies> {
  final ScrollController scrollController = ScrollController();
  final Set<int> _collapsedPostIds = <int>{};

  static const double _treeIndentWidth = 16;
  static const int _maxVisibleIndentLevels = 5;

  void collapseEntry(_ReplyTreeEntry entry) {
    setState(() {
      final int postId = entry.post.no ?? 0;

      if (entry.isCollapsed) {
        _collapsedPostIds.remove(postId);
      } else {
        _collapsedPostIds.add(postId);
      }
    });
  }

  List<_ReplyTreeEntry> _buildReplyEntries(
    int rootPostId,
    List<Post> allPosts,
  ) {
    final Map<int, List<Post>> repliesByParent = buildReplyChildrenIndex(
      allPosts,
    );
    final List<_ReplyTreeEntry> entries = <_ReplyTreeEntry>[];
    final Set<int> visitedPostIds = <int>{rootPostId};
    final Map<int, int> descendantCountCache = <int, int>{};

    int countDescendants(int postId) {
      final int? cachedCount = descendantCountCache[postId];

      if (cachedCount != null) {
        return cachedCount;
      }

      final List<Post> children = repliesByParent[postId] ?? const <Post>[];
      int total = 0;

      for (final Post child in children) {
        final int? childId = child.no;

        if (childId == null) {
          continue;
        }

        total += 1 + countDescendants(childId);
      }

      descendantCountCache[postId] = total;
      return total;
    }

    void addChildren(int parentId, List<bool> branchState) {
      final List<Post> children = repliesByParent[parentId] ?? const <Post>[];

      for (int index = 0; index < children.length; index++) {
        final Post child = children[index];
        final int? childId = child.no;

        if (childId == null || !visitedPostIds.add(childId)) {
          continue;
        }

        final bool hasNextSibling = index < children.length - 1;
        final List<bool> childBranchState = <bool>[
          ...branchState,
          hasNextSibling,
        ];
        final bool hasChildren =
            (repliesByParent[childId] ?? const <Post>[]).isNotEmpty;

        entries.add(
          _ReplyTreeEntry(
            post: child,
            branchState: childBranchState,
            hasChildren: hasChildren,
            hiddenReplyCount: countDescendants(childId),
            isCollapsed: _collapsedPostIds.contains(childId),
          ),
        );

        if (!_collapsedPostIds.contains(childId)) {
          addChildren(childId, childBranchState);
        }
      }
    }

    addChildren(rootPostId, const <bool>[]);

    return entries;
  }

  Widget _buildTreeBranch(
    List<bool> branchState,
    bool isDark,
    _ReplyTreeEntry entry,
  ) {
    if (branchState.isEmpty) {
      return const SizedBox.shrink();
    }

    final int hiddenLevels = branchState.length > _maxVisibleIndentLevels
        ? branchState.length - _maxVisibleIndentLevels
        : 0;
    final List<bool> visibleBranchState = hiddenLevels > 0
        ? branchState.sublist(branchState.length - _maxVisibleIndentLevels)
        : branchState;

    final bool isCollapsed = entry.isCollapsed;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int index = 0; index < visibleBranchState.length; index++)
          SizedBox(
            width: _treeIndentWidth,
            child: index == visibleBranchState.length - 1
                ? Center(
                    child: Icon(
                      isCollapsed
                          ? CupertinoIcons.list_bullet_indent
                          : CupertinoIcons.arrow_turn_down_right,
                      size: _treeIndentWidth,
                      color: isDark
                          ? CupertinoColors.systemGrey.withValues(alpha: 0.45)
                          : const Color(0x22000000),
                    ),
                  )
                : Container(),
          ),
      ],
    );
  }

  Widget _buildCollapsedCard(_ReplyTreeEntry entry, bool isDark) {
    final Color backgroundColor = isDark
        ? const Color(0xFF13161B)
        : const Color(0xFFFFFFFF);
    final Color borderColor = isDark
        ? CupertinoColors.systemGrey.withValues(alpha: 0.25)
        : const Color(0x14000000);
    final Color secondaryText = isDark
        ? CupertinoColors.systemGrey
        : const Color(0xFF5B6470);

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        '${entry.hiddenReplyCount + 1} hidden ${entry.hiddenReplyCount == 0 ? 'reply' : 'replies'}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: secondaryText,
        ),
      ),
    );
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final bool isDark = theme == ThemeData.dark();
    final int rootPostId = widget.post.no ?? 0;
    final List<_ReplyTreeEntry> replyEntries = _buildReplyEntries(
      rootPostId,
      widget.allPosts,
    );

    return GlassScaffold(
      backgroundColor: AppColors.pageBackground(
        Theme.of(context).brightness == Brightness.dark,
      ),
      appBar: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: GlassAppBar(
          title: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              'Replies to #${widget.post.no}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                overflow: TextOverflow.ellipsis,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
          ),
          leading: GlassButton(
            icon: const Icon(CupertinoIcons.back),
            onTap: () => Navigator.of(context).pop(),
            width: 40,
            height: 40,
            iconSize: 20,
          ),
        ),
      ),
      body: Scrollbar(
        controller: scrollController,
        child: replyEntries.isEmpty
            ? Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  MediaQuery.paddingOf(context).top + 44 + 8,
                  20,
                  24,
                ),
                child: const Text(
                  'No threaded replies were found for this post.',
                  style: TextStyle(fontSize: 14),
                ),
              )
            : ListView.builder(
                controller: scrollController,
                itemCount: replyEntries.length,
                itemBuilder: (BuildContext context, int index) {
                  final _ReplyTreeEntry entry = replyEntries[index];

                  return Padding(
                    padding: EdgeInsets.only(
                      left: 8.0,
                      top: index == 0
                          ? MediaQuery.paddingOf(context).top + 44 + 8
                          : 0,
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => collapseEntry(entry),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 15),
                            child: _buildTreeBranch(
                              entry.branchState,
                              isDark,
                              entry,
                            ),
                          ),
                          Expanded(
                            child: entry.isCollapsed
                                ? _buildCollapsedCard(entry, isDark)
                                : ThreadPagePost(
                                    board: widget.board,
                                    thread: widget.thread,
                                    post: entry.post,
                                    allPosts: widget.allPosts,
                                    onDismiss: (int? postId) {},
                                  ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
