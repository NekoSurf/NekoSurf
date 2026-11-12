/// What's remembered about a thread that's been open.
class ThreadMemory {
  ThreadMemory({
    this.newestPost,
    this.firstNewestPost,
    this.knownReplies,
    Set<int>? unseen,
    Set<String>? folded,
    Map<int, int>? primaryParents,
    Set<int>? hiddenPosts,
    Set<String>? hiddenIds,
    this.topPost,
    this.topPath,
    this.topAlignment,
    DateTime? lastRead,
    DateTime? changedAt,
  }) : unseen = unseen ?? <int>{},
       folded = folded ?? <String>{},
       primaryParents = primaryParents ?? <int, int>{},
       hiddenPosts = hiddenPosts ?? <int>{},
       hiddenIds = hiddenIds ?? <String>{},
       lastRead = lastRead ?? DateTime.now(),
       changedAt = changedAt ?? lastRead ?? DateTime.now();

  factory ThreadMemory.fromJson(Map<String, dynamic> json) {
    return ThreadMemory(
      newestPost: json['newest'] as int?,
      firstNewestPost: json['firstNewest'] as int?,
      knownReplies: json['replies'] as int?,
      unseen: (json['unseen'] as List<dynamic>?)?.cast<int>().toSet(),
      folded: (json['folded'] as List<dynamic>?)?.cast<String>().toSet(),
      primaryParents: (json['primary'] as Map<String, dynamic>?)?.map(
        (String post, dynamic parent) =>
            MapEntry<int, int>(int.parse(post), parent as int),
      ),
      hiddenPosts: (json['hidden'] as List<dynamic>?)?.cast<int>().toSet(),
      hiddenIds: (json['hiddenIds'] as List<dynamic>?)?.cast<String>().toSet(),
      topPost: json['topPost'] as int?,
      topPath: json['topPath'] as String?,
      topAlignment: (json['topAlignment'] as num?)?.toDouble(),
      lastRead: DateTime.tryParse(json['lastRead'] as String? ?? ''),
      changedAt: DateTime.tryParse(json['changedAt'] as String? ?? ''),
    );
  }

  int? newestPost;

  /// The newest post when it was first read: those after it are new, the
  /// rest of [unseen] were there but not read. Null if it was first read
  /// before this was kept, when [unseen] only held new posts.
  int? firstNewestPost;

  /// How many replies the thread had when it was last loaded.
  int? knownReplies;

  /// Posts that haven't been on screen: those there when it was first read,
  /// other than the opening post, and those posted since.
  final Set<int> unseen;

  /// The rows folded, and where posts were moved to show in full, by their
  /// place in the nested list.
  final Set<String> folded;
  final Map<int, int> primaryParents;

  /// Posts hidden in it one by one, and the IDs whose posts are.
  final Set<int> hiddenPosts;
  final Set<String> hiddenIds;

  /// The row at the top of the screen, and how far down the screen it starts.
  int? topPost;
  String? topPath;
  double? topAlignment;

  /// When it was last open, to forget it after a while.
  DateTime lastRead;

  /// When anything in it last changed, on any device: iCloud sync keeps the
  /// newest.
  DateTime changedAt;

  Map<String, dynamic> toJson() {
    return {
      if (newestPost != null) 'newest': newestPost,
      if (firstNewestPost != null) 'firstNewest': firstNewestPost,
      if (knownReplies != null) 'replies': knownReplies,
      'unseen': unseen.toList(),
      'folded': folded.toList(),
      'primary': <String, int>{
        for (final MapEntry<int, int> entry in primaryParents.entries)
          '${entry.key}': entry.value,
      },
      if (hiddenPosts.isNotEmpty) 'hidden': hiddenPosts.toList(),
      if (hiddenIds.isNotEmpty) 'hiddenIds': hiddenIds.toList(),
      if (topPost != null) 'topPost': topPost,
      if (topPath != null) 'topPath': topPath,
      if (topAlignment != null) 'topAlignment': topAlignment,
      'lastRead': lastRead.toIso8601String(),
      'changedAt': changedAt.toIso8601String(),
    };
  }
}
