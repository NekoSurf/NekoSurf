class WatchedPosts {
  WatchedPosts({
    required this.postIndex,
    required this.thread,
    required this.watchedAt,
  });

  factory WatchedPosts.fromJson(Map<String, dynamic> json) {
    return WatchedPosts(
      postIndex: json['postIndex'] as int,
      thread: json['thread'] as int,
      watchedAt: DateTime.parse(json['watchedAt'] as String),
    );
  }

  final int postIndex;
  final int thread;
  final DateTime watchedAt;

  Map<String, dynamic> toJson() {
    return {
      'postIndex': postIndex,
      'thread': thread,
      'watchedAt': watchedAt.toIso8601String(),
    };
  }
}
