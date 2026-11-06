import 'package:flutter/widgets.dart';
import 'package:flutter_chan/chan/post.dart';

/// Pages any part of the app can open, without depending on them; the app's
/// `onGenerateRoute` (home/routes.dart) builds them.
sealed class Destination {
  const Destination();

  static const String routeName = '/open';
}

class ThreadDestination extends Destination {
  const ThreadDestination(this.post, this.atPost);

  /// What's known of the thread's opening post; [Post.board] and [Post.no] are
  /// enough, and it's named once it's loaded.
  final Post post;
  final int? atPost;
}

class BoardDestination extends Destination {
  const BoardDestination(this.board, this.name);

  final String board;
  final String name;
}

/// Opens the thread [post] opens. With [atPost] it shows that post once it's
/// loaded, instead of resuming where it was left.
void openThread(BuildContext context, Post post, {int? atPost}) {
  Navigator.of(context).pushNamed(
    Destination.routeName,
    arguments: ThreadDestination(post, atPost),
  );
}

void openBoard(BuildContext context, String board, {String? name}) {
  Navigator.of(context).pushNamed(
    Destination.routeName,
    arguments: BoardDestination(board, name ?? '/$board/'),
  );
}
