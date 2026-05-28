class Bookmark {
  Bookmark({
    this.no,
    this.sub,
    this.com,
    this.imageUrl,
    this.board,
    this.lastSeenReplyCount,
    this.lastSeenImageCount,
  });

  factory Bookmark.fromJson(Map<String, dynamic> json) {
    return Bookmark(
      no: json['no'] as int?,
      sub: json['sub'] as String?,
      com: json['com'] as String?,
      imageUrl: json['imageUrl'] as String?,
      board: json['board'] as String?,
      lastSeenReplyCount: json['lastSeenReplyCount'] as int?,
      lastSeenImageCount: json['lastSeenImageCount'] as int?,
    );
  }

  int? no;
  String? sub;
  String? com;
  String? imageUrl;
  String? board;
  int? lastSeenReplyCount;
  int? lastSeenImageCount;

  Map<String, dynamic> toJson() {
    return {
      'no': no,
      'sub': sub,
      'com': com,
      'imageUrl': imageUrl,
      'board': board,
      'lastSeenReplyCount': lastSeenReplyCount,
      'lastSeenImageCount': lastSeenImageCount,
    };
  }
}
