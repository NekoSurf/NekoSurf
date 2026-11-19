// Quote links in threads read from an archive, written as 4chan writes them,
// so posts show and open them like any other.

/// A quote of [post] (`>>123`): to it in the thread if it's [here], or to the
/// thread of that number on [board] otherwise, as a quote of another thread
/// usually is of its opening post.
String quoteLink(int post, {required String board, required Set<int> here}) =>
    here.contains(post)
    ? '<a href="#p$post" class="quotelink">&gt;&gt;$post</a>'
    : '<a href="/$board/thread/$post" class="quotelink">&gt;&gt;$post</a>';

/// A link to [board] (`>>>/g/`), or to [post]'s thread on it (`>>>/g/123`),
/// taken to be the thread of that number.
String boardLink(String board, int? post) {
  final String href = post == null
      ? '//boards.4chan.org/$board/'
      : '/$board/thread/$post';
  return '<a href="$href" class="quotelink">&gt;&gt;&gt;/$board/${post ?? ''}</a>';
}
