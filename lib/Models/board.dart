class Board {
  Board({
    this.board,
    this.title,
    this.wsBoard,
    this.perPage,
    this.pages,
    this.maxFileSize,
    this.maxWebmFileSize,
    this.maxCommentChars,
    this.maxWebmDuration,
    this.bumpLimit,
    this.imageLimit,
    this.threadsCooldown,
    this.repliesCooldown,
    this.imagesCooldown,
    this.metaDescription,
    this.isArchived,
    this.forcedAnon,
    this.countryFlags,
    this.userIds,
    this.spoilers,
    this.customSpoilers,
  });

  factory Board.fromJson(Map<String, dynamic> json) {
    return Board(
      board: json['board'] as String?,
      title: json['title'] as String?,
      wsBoard: json['ws_board'] as int?,
      perPage: json['per_page'] as int?,
      pages: json['pages'] as int?,
      maxFileSize: json['max_filesize'] as int?,
      maxWebmFileSize: json['max_webm_filesize'] as int?,
      maxCommentChars: json['max_comment_chars'] as int?,
      maxWebmDuration: json['max_webm_duration'] as int?,
      bumpLimit: json['bump_limit'] as int?,
      imageLimit: json['image_limit'] as int?,
      threadsCooldown: json['cooldowns']['threads'] as int?,
      repliesCooldown: json['cooldowns']['replies'] as int?,
      imagesCooldown: json['cooldowns']['images'] as int?,
      metaDescription: json['meta_description'] as String?,
      isArchived: json['is_archived'] as int?,
      forcedAnon: json['forced_anon'] as int?,
      countryFlags: json['country_flags'] as int?,
      userIds: json['user_ids'] as int?,
      spoilers: json['spoilers'] as int?,
      customSpoilers: json['custom_spoilers'] as int?,
    );
  }
  final String? board;
  final String? title;
  final int? wsBoard;
  final int? perPage;
  final int? pages;
  final int? maxFileSize;
  final int? maxWebmFileSize;
  final int? maxCommentChars;
  final int? maxWebmDuration;
  final int? bumpLimit;
  final int? imageLimit;
  final int? threadsCooldown;
  final int? repliesCooldown;
  final int? imagesCooldown;
  final String? metaDescription;
  final int? isArchived;
  final int? forcedAnon;
  final int? countryFlags;
  final int? userIds;
  final int? spoilers;
  final int? customSpoilers;

  Map<String, dynamic> toJson() {
    return {'board': board, 'title': title, 'ws_board': wsBoard};
  }
}
