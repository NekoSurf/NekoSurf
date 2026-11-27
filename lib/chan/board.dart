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

/// What a board is about, from 4chan's [description] of it (as plain text):
/// without the board's name and "is 4chan's imageboard for" before it,
/// which repeat what its row already says. "/3/ - 3DCG" is 4chan's board for
/// 3D modeling and imagery." gives "3D modeling and imagery." A description
/// worded otherwise keeps what's left as it is.
String boardBlurb(String description) {
  final String text = description.trim();
  // The name, quoted, comes first: "/3/ - 3DCG".
  final int named = text.indexOf(' is ');
  if (named < 0 || named > 60) {
    return text;
  }
  String s = text.substring(named + 4);
  for (final RegExp lead in _blurbLeads) {
    s = s.replaceFirst(lead, '');
  }
  s = s.trim();
  if (s.isEmpty) {
    return text;
  }
  return s[0].toUpperCase() + s.substring(1);
}

/// What [boardBlurb] takes off the front, in turn.
final List<RegExp> _blurbLeads = [
  RegExp(r"^(?:4chan's|a|the)\s+", caseSensitive: false),
  // "board for", "imageboard dedicated to", "upload board for", and the
  // odd "imageboard imageboard".
  RegExp(
    r'^(?:\w+\s+)?(?:image)?board(?:\s+imageboard)?,?\s+(?=(?:for|dedicated to)\b)',
  ),
  RegExp(r'^(?:dedicated to|for)\s+'),
  RegExp(r'^the\s+(?:discussion|sharing|posting)\s+of\s+'),
  RegExp(r'^discussing(?:\s+and\s+debating)?\s+'),
  // Not "sharing and critiquing photos".
  RegExp(
    r'^(?:posting|sharing)\s+(?!and\b)(?:(?:pictures|images)\s+of\s+)?',
    caseSensitive: false,
  ),
];
