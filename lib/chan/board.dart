class Board {
  Board({
    required this.board,
    required this.title,
    this.wsBoard,
    this.metaDescription,
    this.isArchived,
  });

  factory Board.fromJson(Map<String, dynamic> json) {
    return Board(
      board: json['board'] as String,
      title: json['title'] as String,
      wsBoard: json['ws_board'] as int?,
      metaDescription: json['meta_description'] as String?,
      isArchived: json['is_archived'] as int?,
    );
  }

  final String board;
  final String title;
  final int? wsBoard;
  final String? metaDescription;
  final int? isArchived;

  /// 4chan calls the others worksafe.
  bool get isNsfw => wsBoard == 0;

  bool get hasArchive => isArchived == 1;
}
