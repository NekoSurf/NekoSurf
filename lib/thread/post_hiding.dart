import 'package:flutter/foundation.dart';
import 'package:flutter_chan/chan/post.dart';

/// What a [PostFilter] looks at.
enum PostFilterKind {
  /// The post's title and text, by keyword or regex.
  text,

  /// The name it was posted under.
  name,

  /// The tripcode it was posted with.
  trip,

  /// The country it was posted from, by name.
  country,
}

/// Hides the posts it matches, in every thread.
@immutable
class PostFilter {
  PostFilter(this.kind, String value) : value = value.trim();

  /// One as [stored] says it; null if that isn't one.
  static PostFilter? parse(String stored) {
    final int colon = stored.indexOf(':');
    if (colon < 0) {
      return null;
    }
    final String kind = stored.substring(0, colon);
    final String value = stored.substring(colon + 1);
    for (final PostFilterKind each in PostFilterKind.values) {
      if (each.name == kind && value.trim().isNotEmpty) {
        return PostFilter(each, value);
      }
    }
    return null;
  }

  final PostFilterKind kind;

  /// The keyword or regex, name, tripcode or country.
  final String value;

  String get stored => '${kind.name}:$value';

  // Invalid regex is taken as a plain keyword, as for hidden threads.
  late final RegExp _text = () {
    try {
      return RegExp(value, caseSensitive: false);
    } on FormatException {
      return RegExp(RegExp.escape(value), caseSensitive: false);
    }
  }();

  bool matches(Post post) => switch (kind) {
    PostFilterKind.text => _text.hasMatch(
      '${post.subject ?? ''}\n${post.commentText}',
    ),
    PostFilterKind.name => post.name != null && post.posterName == value,
    PostFilterKind.trip => post.trip == value,
    PostFilterKind.country => post.countryName == value,
  };

  /// What it is, in a word or a few, like a name or “a keyword”.
  String get label => switch (kind) {
    PostFilterKind.text => '“$value”',
    PostFilterKind.name || PostFilterKind.trip => value,
    PostFilterKind.country => 'From $value',
  };

  @override
  bool operator ==(Object other) =>
      other is PostFilter && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

/// What's hidden in a thread: the posts and IDs hidden there, and the filters
/// for every thread.
class PostHiding {
  const PostHiding({
    this.filters = const <PostFilter>[],
    this.posts = const <int>{},
    this.ids = const <String>{},
  });

  final List<PostFilter> filters;

  /// Posts hidden one by one, by their number.
  final Set<int> posts;

  /// IDs whose posts are hidden: an ID only means a poster in its own thread.
  final Set<String> ids;

  /// Why each of [thread]'s posts that's hidden is; see [reasonFor]. Its first
  /// post never is: a thread is hidden from its board.
  Map<int, String> reasonsIn(List<Post> thread) => <int, String>{
    for (final Post post in thread.skip(1))
      if (reasonFor(post) case final String reason) post.no: reason,
  };

  /// Why [post] is hidden, as a line to show in its place; null if it isn't.
  String? reasonFor(Post post) {
    if (posts.contains(post.no)) {
      return 'Hidden by you';
    }
    final String? id = post.id;
    if (id != null && ids.contains(id)) {
      return 'Hidden · ID:$id';
    }
    for (final PostFilter filter in filters) {
      if (filter.matches(post)) {
        return 'Hidden · ${filter.label}';
      }
    }
    return null;
  }
}
