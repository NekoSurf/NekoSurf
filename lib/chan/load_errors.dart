/// 4chan answered with [statusCode] instead of the [what] asked for.
class ApiException implements Exception {
  const ApiException(this.statusCode, this.what);

  final int statusCode;
  final String what;

  /// 4chan's servers limit how often they're asked; this is them saying no.
  bool get isRateLimited => statusCode == 429;

  @override
  String toString() => "Couldn't load the $what (HTTP $statusCode).";
}

/// The thread was deleted or has dropped out of the archive.
class ThreadNotFound implements Exception {
  const ThreadNotFound();

  @override
  String toString() =>
      'The thread was deleted or has dropped out of the '
      'archive.';
}
