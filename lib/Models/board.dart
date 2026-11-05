class Board {
  Board({
    this.board,
    this.title,
    this.wsBoard,
    this.pages,
    this.metaDescription,
    this.isArchived,
  });

  factory Board.fromJson(Map<String, dynamic> json) {
    return Board(
      board: json['board'] as String?,
      title: json['title'] as String?,
      wsBoard: json['ws_board'] as int?,
      pages: json['pages'] as int?,
      metaDescription: json['meta_description'] as String?,
      isArchived: json['is_archived'] as int?,
    );
  }
  final String? board;
  final String? title;
  final int? wsBoard;
  final int? pages;
  final String? metaDescription;
  final int? isArchived;

  Map<String, dynamic> toJson() {
    return {'board': board, 'title': title, 'ws_board': wsBoard};
  }
}
