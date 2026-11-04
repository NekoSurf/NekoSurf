final RegExp _htmlTag = RegExp('<[^>]*>', multiLine: true);
final RegExp _quoteLink = RegExp(r'>>(\d+)');

String cleanTags(String body) {
  return body.replaceAll(_htmlTag, '');
}

String unescape(String body) {
  return body
      .replaceAll('&gt;', '>')
      .replaceAll('&lt;', '<')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#47;', '/')
      .replaceAll('&#92;', r'\\')
      .replaceAll('&#039;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&copy;', '©');
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
