import 'package:flutter_chan/chan/post.dart';

class Bookmark {
  Bookmark({
    required this.board,
    required this.no,
    this.sub,
    this.com,
    this.imageUrl,
    this.addedAt,
  });

  factory Bookmark.fromJson(Map<String, dynamic> json) {
    return Bookmark(
      no: json['no'] as int,
      sub: json['sub'] as String?,
      com: json['com'] as String?,
      imageUrl: json['imageUrl'] as String?,
      board: json['board'] as String,
      addedAt: (json['addedAt'] as num?)?.toInt(),
    );
  }

  factory Bookmark.fromPost(Post op) => Bookmark(
    board: op.board,
    no: op.no,
    sub: op.sub,
    com: op.com,
    imageUrl: op.thumbnailName,
  );

  final int no;
  final String? sub;
  final String? com;

  /// The stored name of its thumbnail; see [Post.thumbnailName].
  final String? imageUrl;
  final String board;

  /// When it was bookmarked (milliseconds since 1970), on whichever device,
  /// for the same order on all of them. Ones from before that was kept are
  /// numbered from 1, in the order a device had them (see
  /// BookmarksProvider).
  final int? addedAt;

  /// It, bookmarked at [time].
  Bookmark addedAtTime(int time) => Bookmark(
    board: board,
    no: no,
    sub: sub,
    com: com,
    imageUrl: imageUrl,
    addedAt: time,
  );

  /// The thread it's for; two bookmarks with the same key are the same.
  String get key => '$board/$no';

  /// What's known of the thread's opening post.
  Post toPost() => Post.remembered(
    board: board,
    no: no,
    sub: sub,
    com: com,
    thumbnailName: imageUrl,
  );

  Map<String, dynamic> toJson() {
    return {
      'no': no,
      'sub': sub,
      'com': com,
      'imageUrl': imageUrl,
      'board': board,
      if (addedAt != null) 'addedAt': addedAt,
    };
  }
}
