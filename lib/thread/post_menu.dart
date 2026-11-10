import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/history/watched_posts_model.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/thread/post_hiding.dart';
import 'package:flutter_chan/thread/posts_by_id_page.dart';
import 'package:flutter_chan/thread/thread_posts.dart';
import 'package:flutter_chan/ui/back_swipe_route.dart';
import 'package:flutter_chan/ui/dash_menu.dart';
import 'package:flutter_chan/ui/toast.dart';
import 'package:provider/provider.dart';

/// How much of a post's text a filter made from it keeps: copied text starts
/// the same, so that's enough to catch it.
const int _textFilterLength = 80;

/// What holding [post] offers: the other posts by its ID, and hiding it or
/// posts like it, or showing them again. [anchor] is the post, which lifts
/// off the page as [preview] builds it, with the menu under it.
///
/// Completes once the menu has gone.
Future<void> showPostMenu(
  BuildContext anchor, {
  required Post post,
  required ThreadPosts thread,
  required WidgetBuilder preview,
}) {
  final SettingsProvider settings = Provider.of<SettingsProvider>(
    anchor,
    listen: false,
  );
  final WatchedPostsProvider watched = Provider.of<WatchedPostsProvider>(
    anchor,
    listen: false,
  );
  final memory = watched.threadMemory(thread.number);
  final String? id = post.id;
  final String? trip = post.trip;
  final String? name = post.name == null || post.posterName == 'Anonymous'
      ? null
      : post.posterName;
  final String? country = post.countryName;
  final String text = post.commentText.characters
      .take(_textFilterLength)
      .toString();

  DashMenuEntry filterEntry(PostFilter filter, String what, IconData icon) {
    final bool isOn = settings.postFilters.contains(filter);
    return DashMenuEntry(
      title: '${isOn ? 'Show' : 'Hide'} $what',
      icon: isOn ? CupertinoIcons.eye : icon,
      onPressed: () {
        if (isOn) {
          settings.removePostFilter(filter);
        } else {
          showToast(anchor, 'Hidden in every thread');
          settings.addPostFilter(filter);
        }
      },
    );
  }

  final bool isPostHidden = memory?.hiddenPosts.contains(post.no) ?? false;
  final bool isIdHidden =
      id != null && (memory?.hiddenIds.contains(id) ?? false);
  final int idPosts = id == null ? 0 : thread.postsById[id]?.length ?? 0;

  return showLiftedMenu(
    anchor,
    preview: preview,
    entries: [
      if (id != null)
        DashMenuEntry(
          title: idPosts == 1
              ? '1 post by this ID'
              : '$idPosts posts by this ID',
          icon: CupertinoIcons.person_crop_circle,
          onPressed: () => Navigator.of(anchor).push(
            BackSwipePageRoute<void>(
              builder: (_) => PostsByIdPage(id: id, thread: thread),
            ),
          ),
        ),
      // The opening post is the thread: that's hidden from its board.
      if (post.no != thread.number)
        DashMenuEntry(
          title: isPostHidden ? 'Show this post' : 'Hide this post',
          icon: isPostHidden ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
          onPressed: () {
            if (!isPostHidden) {
              showToast(anchor, 'Hidden in this thread');
            }
            watched.setPostHidden(
              thread.number,
              post.no,
              hidden: !isPostHidden,
            );
          },
        ),
      if (id != null)
        DashMenuEntry(
          title: '${isIdHidden ? 'Show' : 'Hide'} ID:$id',
          icon: isIdHidden
              ? CupertinoIcons.eye
              : CupertinoIcons.person_crop_circle_badge_xmark,
          onPressed: () {
            if (!isIdHidden) {
              showToast(anchor, 'Hidden in this thread');
            }
            watched.setIdHidden(thread.number, id, hidden: !isIdHidden);
          },
        ),
      if (trip != null)
        filterEntry(
          PostFilter(PostFilterKind.trip, trip),
          'posts by $trip',
          CupertinoIcons.person_badge_minus,
        )
      else if (name != null)
        filterEntry(
          PostFilter(PostFilterKind.name, name),
          'posts by $name',
          CupertinoIcons.person_badge_minus,
        ),
      if (country != null)
        filterEntry(
          PostFilter(PostFilterKind.country, country),
          'posts from $country',
          CupertinoIcons.flag_slash,
        ),
      if (text.isNotEmpty)
        filterEntry(
          PostFilter(PostFilterKind.text, RegExp.escape(text)),
          'posts with this text',
          CupertinoIcons.text_badge_xmark,
        ),
    ],
  );
}
