class WatchedPosts {
  WatchedPosts({
    required this.postIndex,
    required this.thread,
    required this.watchedAt,
    int? furthestIndex,
  }) : furthestIndex = furthestIndex ?? postIndex;

  factory WatchedPosts.fromJson(Map<String, dynamic> json) {
    return WatchedPosts(
      postIndex: json['postIndex'] as int,
      thread: json['thread'] as int,
      watchedAt: DateTime.parse(json['watchedAt'] as String),
      furthestIndex: json['furthestIndex'] as int?,
    );
  }

  final int postIndex;
  final int thread;
  final DateTime watchedAt;

  /// The furthest post ever reached, unlike [postIndex] (where to resume),
  /// which moves back up when you scroll up. Used to count new replies.
  final int furthestIndex;

  Map<String, dynamic> toJson() {
    return {
      'postIndex': postIndex,
      'thread': thread,
      'watchedAt': watchedAt.toIso8601String(),
      'furthestIndex': furthestIndex,
    };
  }
}
