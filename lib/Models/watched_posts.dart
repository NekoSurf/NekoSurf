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

/// What's remembered about a thread besides how far it was read.
class ThreadMemory {
  ThreadMemory({this.newestPost, this.knownReplies, Set<int>? unseen})
    : unseen = unseen ?? <int>{};

  factory ThreadMemory.fromJson(Map<String, dynamic> json) {
    return ThreadMemory(
      newestPost: json['newest'] as int?,
      knownReplies: json['replies'] as int?,
      unseen: (json['unseen'] as List<dynamic>?)?.cast<int>().toSet(),
    );
  }

  /// The newest post known in the thread.
  int? newestPost;

  /// How many replies the thread had when it was last loaded.
  int? knownReplies;

  /// Posts since then that haven't been on screen.
  final Set<int> unseen;

  Map<String, dynamic> toJson() {
    return {
      if (newestPost != null) 'newest': newestPost,
      if (knownReplies != null) 'replies': knownReplies,
      'unseen': unseen.toList(),
    };
  }
}
