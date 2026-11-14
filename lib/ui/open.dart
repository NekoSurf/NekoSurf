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

/// Builds the page for a [Destination], for a pane to show it in place
/// rather than on a new route; the app (home/routes.dart) gives it.
class DestinationPages extends InheritedWidget {
  const DestinationPages({
    super.key,
    required this.pageFor,
    required super.child,
  });

  final Widget Function(Destination destination) pageFor;

  static DestinationPages? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DestinationPages>();

  @override
  bool updateShouldNotify(DestinationPages oldWidget) =>
      pageFor != oldWidget.pageFor;
}

/// Around a list with a pane beside it (see MasterDetail in
/// ui/master_detail.dart): threads opened from the list show in the pane,
/// in place of the one there.
class DetailPane extends InheritedWidget {
  const DetailPane({super.key, required this.show, required super.child});

  final void Function(Destination destination) show;

  static DetailPane? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DetailPane>();

  @override
  bool updateShouldNotify(DetailPane oldWidget) => show != oldWidget.show;
}

/// Opens the thread [post] opens. With [atPost] it shows that post once it's
/// loaded, instead of resuming where it was left. From a list with a pane
/// beside it, it shows there.
void openThread(BuildContext context, Post post, {int? atPost}) {
  final DetailPane? pane = DetailPane.maybeOf(context);
  if (pane != null) {
    pane.show(ThreadDestination(post, atPost));
    return;
  }
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
