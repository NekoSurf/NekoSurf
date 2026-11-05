final RegExp _boardLink = RegExp(
  r'^(?:https?:)?(?://boards\.4chan(?:nel)?\.org)?/(\w+)/'
  r'(?:thread/(\d+)[^#]*(?:#[pq](\d+))?|catalog\S*|#\S*)?$',
);

/// Where a link in a post goes: a board, or a thread on it and maybe a post in
/// that. Null for anything else, like a post in the same thread ("#p123").
({String board, int? thread, int? post})? parseBoardLink(String href) {
  final Match? match = _boardLink.firstMatch(href);
  if (match == null) {
    return null;
  }
  return (
    board: match.group(1)!,
    thread: int.tryParse(match.group(2) ?? ''),
    post: int.tryParse(match.group(3) ?? ''),
  );
}
