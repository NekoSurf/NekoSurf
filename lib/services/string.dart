String cleanTags(String body) {
  return body.replaceAll(RegExp('<[^>]*>', multiLine: true), '');
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

  final String text = unescape(cleanTags(body));
  final Set<int> uniqueIds = <int>{};
  final List<int> orderedIds = <int>[];

  for (final Match match in RegExp(r'>>(\d+)').allMatches(text)) {
    final int? postId = int.tryParse(match.group(1) ?? '');

    if (postId != null && uniqueIds.add(postId)) {
      orderedIds.add(postId);
    }
  }

  return orderedIds;
}
