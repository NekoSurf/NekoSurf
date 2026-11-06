import 'package:flutter_chan/chan/post.dart';

class Bookmark {
  Bookmark({
    required this.board,
    required this.no,
    this.sub,
    this.com,
    this.imageUrl,
  });

  factory Bookmark.fromJson(Map<String, dynamic> json) {
    return Bookmark(
      no: json['no'] as int,
      sub: json['sub'] as String?,
      com: json['com'] as String?,
      imageUrl: json['imageUrl'] as String?,
      board: json['board'] as String,
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
    };
  }
}
