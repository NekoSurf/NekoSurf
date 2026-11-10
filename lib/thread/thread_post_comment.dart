import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/chan/board_link.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/chan/post_text.dart';
import 'package:flutter_chan/thread/quoted_post_page.dart';
import 'package:flutter_chan/thread/spoiler_text.dart';
import 'package:flutter_chan/thread/thread_posts.dart';
import 'package:flutter_chan/ui/back_swipe_route.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/open.dart';
import 'package:flutter_chan/ui/open_url.dart';

class ThreadPostComment extends StatefulWidget {
  const ThreadPostComment({
    super.key,
    required this.com,
    required this.thread,
    this.onTap,
    this.onTapQuote,
    this.repliedTo,
  });

  final String com;
  final ThreadPosts thread;

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
  static final RegExp _hrefPattern = RegExp('href="([^"]*)"');
  // With the line breaks around it, which the block has room for by itself.
  static final RegExp _codePattern = RegExp(
    r'(?:<br>)?<pre[^>]*>(.*?)</pre>(?:<br>)?',
    dotAll: true,
  );
  // Stands in for a code block while the comment is split into lines.
  static const String _codeMark = '\u0000';
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
        oldWidget.repliedTo != widget.repliedTo ||
        !identical(oldWidget.thread, widget.thread)) {
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

  List<Widget> _formatComment(String com, bool isDark) {
    _disposeRecognizers();
    final List<Widget> formattedCom = [];

    final List<String> codeBlocks = <String>[];
    final List<String> splittedCom = com
        .replaceAllMapped(_codePattern, (Match match) {
          codeBlocks.add(match.group(1)!);
          return '<br>$_codeMark<br>';
        })
        .split('<br>');
    // Blank lines at either end would only add a gap around the post.
    while (splittedCom.isNotEmpty && _isBlank(splittedCom.last)) {
      splittedCom.removeLast();
    }
    while (splittedCom.isNotEmpty && _isBlank(splittedCom.first)) {
      splittedCom.removeAt(0);
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
      if (line == _codeMark) {
        flushQuotes();
        formattedCom.add(
          _CodeBlock(
            code: plainText(
              codeBlocks.removeAt(0).replaceAll('<br>', '\n'),
            ).trimRight(),
            onTap: _handleTextTap,
          ),
        );
      } else if (soleQuote != null) {
        pendingQuotes.add(
          _QuoteTag(label: widget.thread.labelOf(soleQuote), post: soleQuote),
        );
      } else if (line.contains('<span class="quote">')) {
        flushQuotes();
        final text = plainText(line);
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
          if (match.start > lastEnd) {
            final normalText = plainText(
              remainingText.substring(lastEnd, match.start),
            );
            spans.add(TextSpan(text: normalText, style: _bodyStyle(isDark)));
          }

          final spoilerText = plainText(match.group(1) ?? '');
          spans.add(WidgetSpan(child: SpoilerText(text: spoilerText)));

          lastEnd = match.end;
        }

        if (lastEnd < line.length) {
          final normalText = plainText(remainingText.substring(lastEnd));
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
        final text = plainText(line);

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
  bool _isBlank(String line) => plainText(line).trim().isEmpty;

  /// The post quoted, if a quote is all there is on [line].
  int? _soleQuote(String line) {
    final Match? match = _linkPattern.matchAsPrefix(line.trim());
    if (match == null || match.end != line.trim().length) {
      return null;
    }
    // Elsewhere: it needs saying, so it's shown like any other link.
    if (_elsewhere(match.group(0)!) != null) {
      return null;
    }
    return _quotedPost(match.group(1)!);
  }

  /// Where the link [anchor] goes, if that's outside this thread.
  ({String board, int? thread, int? post})? _elsewhere(String anchor) {
    final String? href = _hrefPattern.firstMatch(anchor)?.group(1);
    final target = href == null ? null : parseBoardLink(href);
    if (target == null ||
        (target.board == widget.thread.board &&
            target.thread == widget.thread.number)) {
      return null;
    }
    return target;
  }

  /// The post a link's text quotes, like `&gt;&gt;123`, if it's one.
  int? _quotedPost(String linkText) {
    final String label = plainText(linkText).trim();
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
          _textSpans(plainText(line.substring(lastEnd, match.start)), isDark),
        );
      }

      final String linkText = match.group(1)!;
      final elsewhere = _elsewhere(match.group(0)!);
      final int? quoted = _quotedPost(linkText);
      final bool isHere = quoted != null && elsewhere == null;
      spans.add(
        TextSpan(
          text: isHere
              ? widget.thread.labelOf(quoted)
              : quoted != null
              ? '${plainText(linkText)} (other thread)'
              : plainText(linkText),
          style: TextStyle(
            color: isHere && _isQuieter(quoted)
                ? DashColors.muted(isDark)
                : _quoteColor(isDark),
            fontWeight: FontWeight.w500,
          ),
          recognizer: isHere
              ? _track(TapGestureRecognizer()..onTap = () => _openQuote(quoted))
              : elsewhere == null
              ? null
              : _track(
                  TapGestureRecognizer()
                    ..onTap = () => _openElsewhere(elsewhere),
                ),
        ),
      );

      lastEnd = match.end;
    }

    if (lastEnd < line.length) {
      spans.addAll(_textSpans(plainText(line.substring(lastEnd)), isDark));
    }

    return spans;
  }

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
            TapGestureRecognizer()..onTap = () => openUrl(url),
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
        builder: (context) => QuotedPostPage(post: post, thread: widget.thread),
      ),
    );
  }

  void _openElsewhere(({String board, int? thread, int? post}) target) {
    final int? thread = target.thread;
    if (thread == null) {
      openBoard(context, target.board);
    } else {
      openThread(
        context,
        Post(no: thread, board: target.board),
        atPost: target.post == thread ? null : target.post,
      );
    }
  }

  /// Whether [post] is quoted beside the post this one is listed under, which
  /// is the one to stand out. If that isn't quoted here, none stands out.
  bool _isQuieter(int post) {
    final int? repliedTo = widget.repliedTo;
    return repliedTo != null &&
        post != repliedTo &&
        extractQuotedPostIds(widget.com).contains(repliedTo);
  }

  // The theme's accent is too pale to read as text on a light background.
  Color _quoteColor(bool isDark) =>
      isDark ? context.accent : context.themeColor.ink;

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
    final bool isDark = context.isDark;
    if (_lines == null || _linesDark != isDark) {
      _lines = _formatComment(widget.com, isDark);
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

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.code, required this.onTap});

  final String code;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: DashColors.muted(isDark).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        code,
        onTap: onTap,
        style: TextStyle(
          color: DashColors.text(isDark),
          fontFamily: Platform.isIOS ? 'Menlo' : 'monospace',
          fontSize: 12.5,
          height: 1.35,
        ),
      ),
    );
  }
}

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
