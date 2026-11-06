import 'package:flutter_chan/chan/post.dart';

enum Sort { byBumpOrder, byReplyCount, byImagesCount, byNewest }

enum SortDirection { asc, desc }

List<Post> sortThreads(
  List<Post> threads,
  Sort sorting,
  SortDirection direction,
) {
  int key(Post post) => switch (sorting) {
    Sort.byBumpOrder => post.lastModified ?? 0,
    Sort.byReplyCount => post.replies ?? 0,
    Sort.byImagesCount => post.images ?? 0,
    Sort.byNewest => post.time ?? 0,
  };

  final List<Post> sorted = List<Post>.of(threads)
    ..sort((a, b) => key(a).compareTo(key(b)));
  return direction == SortDirection.desc ? sorted.reversed.toList() : sorted;
}

List<Post> stickyFirst(List<Post> threads) => [
  ...threads.where((p) => p.isSticky),
  ...threads.where((p) => !p.isSticky),
];

/// Threads whose subject, name and comment together contain every word of
/// [query], in any order and ignoring case, like find.4chan.org matches.
List<Post> filterThreads(List<Post> threads, String query) {
  final List<String> words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) {
    return threads;
  }

  return threads.where((post) {
    final String text = [
      post.subject ?? '',
      post.posterName,
      post.commentText,
    ].join('\n').toLowerCase();
    return words.every(text.contains);
  }).toList();
}
