import 'package:flutter/widgets.dart';
import 'package:flutter_chan/board/board_page.dart';
import 'package:flutter_chan/thread/thread_page.dart';
import 'package:flutter_chan/ui/back_swipe_route.dart';
import 'package:flutter_chan/ui/open.dart';

/// The app's first page, [page], in the same kind of route as the pages
/// opened over it, so it slides out of their way and back like they do.
///
/// CupertinoApp's own route for `home` is another kind, and a page under a
/// page of another kind only borrows that page's slide: on iPhone it hardly
/// moved with a back swipe and jumped when let go, and was rebuilt whole as
/// the slide began and ended; on Android it didn't slide at all.
Route<void> homeRoute(Widget page) => BackSwipePageRoute<void>(
  settings: const RouteSettings(name: Navigator.defaultRouteName),
  builder: (_) => page,
);

/// Builds the pages opened through ui/open.dart.
Route<void>? generateRoute(RouteSettings settings) {
  final Object? destination = settings.arguments;
  if (destination is! Destination) {
    return null;
  }
  return BackSwipePageRoute<void>(
    builder: (_) => switch (destination) {
      ThreadDestination(:final post, :final atPost) => ThreadPage(
        post: post,
        initialPost: atPost,
      ),
      BoardDestination(:final board, :final name) => BoardPage(
        board: board,
        boardName: name,
      ),
    },
  );
}
