final RegExp _htmlTag = RegExp('<[^>]*>', multiLine: true);
final RegExp _quoteLink = RegExp(r'>>(\d+)');

/// [html], as 4chan gives a post's text, as what it reads as.
String plainText(String html) => unescape(html.replaceAll(_htmlTag, ''));

final RegExp _entity = RegExp(r'&(#\d+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);');
const Map<String, String> _namedEntities = <String, String>{
  'gt': '>',
  'lt': '<',
  'amp': '&',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'copy': '©',
};

/// [body] with its HTML entities as the characters they stand for, each once:
/// "&amp;gt;" is someone writing "&gt;", not ">".
String unescape(String body) {
  return body.replaceAllMapped(_entity, (Match match) {
    final String entity = match.group(1)!;
    if (!entity.startsWith('#')) {
      return _namedEntities[entity] ?? match.group(0)!;
    }
    final bool isHex = entity[1] == 'x' || entity[1] == 'X';
    final int? code = int.tryParse(
      entity.substring(isHex ? 2 : 1),
      radix: isHex ? 16 : 10,
    );
    return code == null || code > 0x10FFFF
        ? match.group(0)!
        : String.fromCharCode(code);
  });
}

List<int> extractQuotedPostIds(String? body) {
  if (body == null || body.isEmpty) {
    return const [];
  }

  // A space for each tag, or a line starting with a digit would run into the
  // number quoted on the line before: ">>123<br>4 weeks" isn't a quote of 1234.
  final String text = unescape(body.replaceAll(_htmlTag, ' '));
  final List<int> orderedIds = <int>[];

  for (final Match match in _quoteLink.allMatches(text)) {
    final int? postId = int.tryParse(match.group(1) ?? '');

    if (postId != null) {
      orderedIds.add(postId);
    }
  }

  return orderedIds;
}
