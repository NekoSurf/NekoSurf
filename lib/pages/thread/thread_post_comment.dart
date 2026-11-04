import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:flutter_chan/pages/thread/thread_replied_to.dart';
import 'package:flutter_chan/pages/thread/thread_rows.dart';
import 'package:flutter_chan/services/back_swipe_route.dart';
import 'package:flutter_chan/services/string.dart';
import 'package:flutter_chan/widgets/spoiler_text.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class ThreadPostComment extends StatefulWidget {
  const ThreadPostComment({
    super.key,
    required this.com,
    required this.thread,
    required this.board,
    required this.allPosts,
    this.onTap,
    this.onTapQuote,
    this.repliedTo,
  });

  final String com;
  final int thread;
  final String board;
  final List<Post> allPosts;

  /// A tap on the text, which selectable text would otherwise keep to itself.
  final VoidCallback? onTap;

  /// A tap on a quote, with the post it names. Returns whether it took care of
  /// it: if not, or without this, the post opens on its own page.
  final bool Function(int post)? onTapQuote;

  /// The post this one is listed under here. Its quote stands out from any
  /// others, as the same reply can be listed under several of the posts it
  /// quotes.
  final int? repliedTo;

  @override
  State<ThreadPostComment> createState() => _ThreadPostCommentState();
}

/// Builds the comment's lines once and reuses them until the comment, the
/// theme or the thread's posts change. The thread page rebuilds its visible
/// posts whenever the video preload window moves, i.e. constantly while
/// scrolling, and re-parsing every comment each time showed up as jank.
class _ThreadPostCommentState extends State<ThreadPostComment> {
  static final RegExp _spoilerPattern = RegExp(r'<s>(.*?)</s>');
  static final RegExp _linkPattern = RegExp(r'<a [^>]*>(.*?)</a>');
  static final RegExp _urlPattern = RegExp(
    r'https?://[\w-]+(\.[\w-]+)+([\w.,@?^=%&:/~+#-]*[\w@?^=%&/~+#-])?',
    caseSensitive: false,
  );

  List<Widget>? _lines;
  bool? _linesDark;
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  @override
  void didUpdateWidget(covariant ThreadPostComment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.com != widget.com ||
        oldWidget.thread != widget.thread ||
        oldWidget.board != widget.board ||
        oldWidget.repliedTo != widget.repliedTo ||
        !identical(oldWidget.allPosts, widget.allPosts)) {
      _lines = null;
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final TapGestureRecognizer recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  List<Widget> formatComment(String com, bool isDark) {
    _disposeRecognizers();
    final List<Widget> formattedCom = [];

    final List<String> splittedCom = com.split('<br>');
    // Blank lines at the end would only add a gap below the post.
    while (splittedCom.isNotEmpty && _isBlank(splittedCom.last)) {
      splittedCom.removeLast();
    }

    // Quotes on lines of their own sit side by side, as tags.
    final List<_QuoteTag> pendingQuotes = <_QuoteTag>[];
    void flushQuotes() {
      if (pendingQuotes.isEmpty) {
        return;
      }
      final List<_QuoteTag> tags = List<_QuoteTag>.of(pendingQuotes);
      pendingQuotes.clear();
      formattedCom.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final _QuoteTag tag in tags)
                GestureDetector(
                  onTap: () => _openQuote(tag.post),
                  child: _QuoteChip(
                    label: tag.label,
                    color: _isQuieter(tag.post)
                        ? DashColors.muted(isDark)
                        : _quoteColor(isDark),
                    showArrow: !_isQuieter(tag.post),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    for (final line in splittedCom) {
      final int? soleQuote = _soleQuote(line);
      if (soleQuote != null) {
        pendingQuotes.add(
          _QuoteTag(
            label: postLabel(soleQuote, widget.allPosts),
            post: soleQuote,
          ),
        );
      } else if (line.contains('<span class="quote">')) {
        flushQuotes();
        final text = unescape(cleanTags(line));
        formattedCom.add(
          SelectableText(
            text,
            onTap: _handleTextTap,
            style: _bodyStyle(isDark).copyWith(
              color: isDark ? const Color(0xFF9CBF5B) : const Color(0xFF5F7F1E),
            ),
          ),
        );
      } else if (line.contains('<s>')) {
        flushQuotes();
        final List<InlineSpan> spans = [];
        final String remainingText = line;
        int lastEnd = 0;

        for (final match in _spoilerPattern.allMatches(line)) {
          // Add non-spoiler text before the match
          if (match.start > lastEnd) {
            final normalText = unescape(
              cleanTags(remainingText.substring(lastEnd, match.start)),
            );
            spans.add(TextSpan(text: normalText, style: _bodyStyle(isDark)));
          }

          // Add spoiler text
          final spoilerText = unescape(cleanTags(match.group(1) ?? ''));
          spans.add(WidgetSpan(child: SpoilerText(text: spoilerText)));

          lastEnd = match.end;
        }

        // Add remaining non-spoiler text after the last match
        if (lastEnd < line.length) {
          final normalText = unescape(
            cleanTags(remainingText.substring(lastEnd)),
          );
          spans.add(TextSpan(text: normalText, style: _bodyStyle(isDark)));
        }

        formattedCom.add(
          SelectableText.rich(
            TextSpan(children: spans),
            onTap: _handleTextTap,
            style: _bodyStyle(isDark),
          ),
        );
      } else if (line.contains('<a href')) {
        flushQuotes();
        formattedCom.add(
          Text.rich(
            TextSpan(children: _lineSpans(line, isDark)),
            style: _bodyStyle(isDark),
          ),
        );
      } else if (_isBlank(line)) {
        // A blank line after quotes adds nothing to the room they already have.
        if (pendingQuotes.isEmpty) {
          formattedCom.add(const SizedBox(height: 8));
        }
      } else {
        flushQuotes();
        final text = unescape(cleanTags(line));

        if (!_urlPattern.hasMatch(text)) {
          formattedCom.add(
            SelectableText(
              text,
              onTap: _handleTextTap,
              style: _bodyStyle(isDark),
            ),
          );
        } else {
          formattedCom.add(
            Text.rich(
              TextSpan(children: _textSpans(text, isDark)),
              style: _bodyStyle(isDark),
            ),
          );
        }
      }
    }

    flushQuotes();
    return formattedCom;
  }

  /// Whether [line] shows nothing, like the end of a code block on its own.
  bool _isBlank(String line) => unescape(cleanTags(line)).trim().isEmpty;

  /// The post quoted, if a quote is all there is on [line].
  int? _soleQuote(String line) {
    final Match? match = _linkPattern.matchAsPrefix(line.trim());
    if (match == null || match.end != line.trim().length) {
      return null;
    }
    return _quotedPost(match.group(1)!);
  }

  /// The post a link's text quotes, like `&gt;&gt;123`, if it's one.
  int? _quotedPost(String linkText) {
    final String label = unescape(cleanTags(linkText)).trim();
    return label.startsWith('>>') ? int.tryParse(label.substring(2)) : null;
  }

  /// A line with links: its quotes name their posts and open them when tapped,
  /// as in "#38 and #46 are right". Quotes of another board show as written.
  List<InlineSpan> _lineSpans(String line, bool isDark) {
    final List<InlineSpan> spans = [];
    int lastEnd = 0;

    for (final Match match in _linkPattern.allMatches(line)) {
      if (match.start > lastEnd) {
        spans.addAll(
          _textSpans(
            unescape(cleanTags(line.substring(lastEnd, match.start))),
            isDark,
          ),
        );
      }

      final String linkText = match.group(1)!;
      final int? quoted = _quotedPost(linkText);
      spans.add(
        TextSpan(
          text: quoted != null
              ? postLabel(quoted, widget.allPosts)
              : unescape(cleanTags(linkText)),
          style: TextStyle(
            color: quoted != null && _isQuieter(quoted)
                ? DashColors.muted(isDark)
                : _quoteColor(isDark),
            fontWeight: FontWeight.w500,
          ),
          recognizer: quoted == null
              ? null
              : _track(
                  TapGestureRecognizer()..onTap = () => _openQuote(quoted),
                ),
        ),
      );

      lastEnd = match.end;
    }

    if (lastEnd < line.length) {
      spans.addAll(
        _textSpans(unescape(cleanTags(line.substring(lastEnd))), isDark),
      );
    }

    return spans;
  }

  /// Plain text, with its web addresses opening when tapped.
  List<InlineSpan> _textSpans(String text, bool isDark) {
    final List<InlineSpan> spans = [];
    int lastEnd = 0;

    for (final Match match in _urlPattern.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }

      final String url = text.substring(match.start, match.end);
      spans.add(
        TextSpan(
          text: url,
          style: TextStyle(
            color: isDark ? const Color(0xFF81a2be) : const Color(0xFF1d9bf0),
          ),
          recognizer: _track(
            TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(url)),
          ),
        ),
      );

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return spans;
  }

  void _openQuote(int post) {
    if (widget.onTapQuote?.call(post) ?? false) {
      return;
    }
    Navigator.of(context).push(
      BackSwipePageRoute(
        builder: (context) => ThreadRepliesTo(
          post: post,
          thread: widget.thread,
          board: widget.board,
          allPosts: widget.allPosts,
        ),
      ),
    );
  }

  /// Whether [post] is quoted beside the post this one is listed under, which
  /// is the one to stand out. If that isn't quoted here, none stands out.
  bool _isQuieter(int post) {
    final int? repliedTo = widget.repliedTo;
    return repliedTo != null &&
        post != repliedTo &&
        extractQuotedPostIds(widget.com).contains(repliedTo);
  }

  // The app's accent is too pale to read as text on a light background.
  Color _quoteColor(bool isDark) =>
      isDark ? DashColors.accent : const Color(0xFF0E7C9B);

  TextStyle _bodyStyle(bool isDark) => TextStyle(
    color: DashColors.text(isDark),
    fontSize: 14.5,
    height: 1.4,
    letterSpacing: -0.15,
  );

  void _handleTextTap() => widget.onTap?.call();

  TapGestureRecognizer _track(TapGestureRecognizer recognizer) {
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Provider.of<ThemeChanger>(context).isDark;
    if (_lines == null || _linesDark != isDark) {
      _lines = formatComment(widget.com, isDark);
      _linesDark = isDark;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _lines!,
    );
  }
}

class _QuoteTag {
  const _QuoteTag({required this.label, required this.post});

  final String label;
  final int post;
}

/// A small tag naming a quoted post, which opens it when tapped.
class _QuoteChip extends StatelessWidget {
  const _QuoteChip({
    required this.label,
    required this.color,
    required this.showArrow,
  });

  final String label;
  final Color color;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showArrow) ...[
            Icon(CupertinoIcons.arrow_turn_left_up, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.05,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
