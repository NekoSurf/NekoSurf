// Static regex patterns to avoid recompilation
final RegExp _tagsRegex = RegExp('<[^>]*>', multiLine: true);
final RegExp _quoteRegex = RegExp(r'>>(\d+)');

// Unescape map for batch replacements
const Map<String, String> _unescapeMap = {
  '&gt;': '>',
  '&lt;': '<',
  '&amp;': '&',
  '&quot;': '"',
  '&apos;': "'",
  '&#47;': '/',
  '&#92;': r'\',
  '&#039;': "'",
  '&#39;': "'",
  '&nbsp;': ' ',
  '&copy;': '©',
};

String cleanTags(String body) {
  return body.replaceAll(_tagsRegex, '');
}

String unescape(String body) {
  String result = body;
  for (final entry in _unescapeMap.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  return result;
}

List<int> extractQuotedPostIds(String? body) {
  if (body == null || body.isEmpty) {
    return const [];
  }

  final String text = unescape(cleanTags(body));
  final List<int> orderedIds = <int>[];

  for (final Match match in _quoteRegex.allMatches(text)) {
    final int? postId = int.tryParse(match.group(1) ?? '');

    if (postId != null) {
      orderedIds.add(postId);
    }
  }

  return orderedIds;
}
