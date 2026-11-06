import 'package:flutter/widgets.dart';
import 'package:flutter_chan/board/board_page.dart';
import 'package:flutter_chan/thread/thread_page.dart';
import 'package:flutter_chan/ui/back_swipe_route.dart';
import 'package:flutter_chan/ui/open.dart';

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
