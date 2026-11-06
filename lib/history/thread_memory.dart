/// What's remembered about a thread that's been open.
class ThreadMemory {
  ThreadMemory({
    this.newestPost,
    this.knownReplies,
    Set<int>? unseen,
    Set<String>? folded,
    Map<int, int>? primaryParents,
    this.topPost,
    this.topPath,
    this.topAlignment,
    DateTime? lastRead,
  }) : unseen = unseen ?? <int>{},
       folded = folded ?? <String>{},
       primaryParents = primaryParents ?? <int, int>{},
       lastRead = lastRead ?? DateTime.now();

  factory ThreadMemory.fromJson(Map<String, dynamic> json) {
    return ThreadMemory(
      newestPost: json['newest'] as int?,
      knownReplies: json['replies'] as int?,
      unseen: (json['unseen'] as List<dynamic>?)?.cast<int>().toSet(),
      folded: (json['folded'] as List<dynamic>?)?.cast<String>().toSet(),
      primaryParents: (json['primary'] as Map<String, dynamic>?)?.map(
        (String post, dynamic parent) =>
            MapEntry<int, int>(int.parse(post), parent as int),
      ),
      topPost: json['topPost'] as int?,
      topPath: json['topPath'] as String?,
      topAlignment: (json['topAlignment'] as num?)?.toDouble(),
      lastRead: DateTime.tryParse(json['lastRead'] as String? ?? ''),
    );
  }

  int? newestPost;

  /// How many replies the thread had when it was last loaded.
  int? knownReplies;

  /// Posts since then that haven't been on screen.
  final Set<int> unseen;

  /// The rows folded, and where posts were moved to show in full, by their
  /// place in the nested list.
  final Set<String> folded;
  final Map<int, int> primaryParents;

  /// The row at the top of the screen, and how far down the screen it starts.
  int? topPost;
  String? topPath;
  double? topAlignment;

  /// When it was last open, to forget it after a while.
  DateTime lastRead;

  Map<String, dynamic> toJson() {
    return {
      if (newestPost != null) 'newest': newestPost,
      if (knownReplies != null) 'replies': knownReplies,
      'unseen': unseen.toList(),
      'folded': folded.toList(),
      'primary': <String, int>{
        for (final MapEntry<int, int> entry in primaryParents.entries)
          '${entry.key}': entry.value,
      },
      if (topPost != null) 'topPost': topPost,
      if (topPath != null) 'topPath': topPath,
      if (topAlignment != null) 'topAlignment': topAlignment,
      'lastRead': lastRead.toIso8601String(),
    };
  }
}
