import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:flutter_chan/pages/thread/thread_replied_to.dart';
import 'package:flutter_chan/services/string.dart';
import 'package:flutter_chan/widgets/spoiler_text.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class ThreadPostComment extends StatefulWidget {
  const ThreadPostComment({
    Key? key,
    required this.com,
    required this.thread,
    required this.board,
    required this.allPosts,
  }) : super(key: key);

  final String com;
  final int thread;
  final String board;
  final List<Post> allPosts;

  @override
  State<ThreadPostComment> createState() => _ThreadPostCommentState();
}

/// Builds the comment's lines once and reuses them until the comment, the
/// theme or the thread's posts change. The thread page rebuilds its visible
/// posts whenever the video preload window moves, i.e. constantly while
/// scrolling, and re-parsing every comment each time showed up as jank.
class _ThreadPostCommentState extends State<ThreadPostComment> {
  static final RegExp _spoilerPattern = RegExp(r'<s>(.*?)</s>');
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

    for (final line in splittedCom) {
      if (line.startsWith('<a href')) {
        final urlNo = unescape(cleanTags(line)).replaceFirst('>>', '').trim();

        formattedCom.add(
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ThreadRepliesTo(
                    post: int.parse(urlNo),
                    thread: widget.thread,
                    board: widget.board,
                    allPosts: widget.allPosts,
                  ),
                ),
              );
            },
            child: Text(
              '>> $urlNo',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: DashColors.accent,
              ),
            ),
          ),
        );
      } else if (line.contains('<span class="quote">')) {
        final text = unescape(cleanTags(line));
        formattedCom.add(
          SelectableText(
            text,
            style: const TextStyle(
              color: Color(0xFF789922),
              fontSize: 14,
              height: 1.35,
            ),
          ),
        );
      } else if (line.contains('<s>')) {
        final List<InlineSpan> spans = [];
        final String remainingText = line;
        int lastEnd = 0;

        for (final match in _spoilerPattern.allMatches(line)) {
          // Add non-spoiler text before the match
          if (match.start > lastEnd) {
            final normalText = unescape(
              cleanTags(remainingText.substring(lastEnd, match.start)),
            );
            spans.add(
              TextSpan(
                text: normalText,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
              ),
            );
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
          spans.add(
            TextSpan(
              text: normalText,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
            ),
          );
        }

        formattedCom.add(
          SelectableText.rich(
            TextSpan(children: spans),
            style: const TextStyle(fontSize: 14, height: 1.35),
          ),
        );
      } else if (line.isEmpty) {
        formattedCom.add(const SizedBox(height: 8));
      } else {
        final text = unescape(cleanTags(line));
        final matches = _urlPattern.allMatches(text);

        if (matches.isEmpty) {
          formattedCom.add(
            SelectableText(
              text,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          );
        } else {
          final List<TextSpan> spans = [];
          int lastEnd = 0;

          for (final match in matches) {
            if (match.start > lastEnd) {
              spans.add(
                TextSpan(
                  text: text.substring(lastEnd, match.start),
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                ),
              );
            }

            spans.add(
              TextSpan(
                text: text.substring(match.start, match.end),
                style: TextStyle(
                  color: isDark
                      ? const Color(0xFF81a2be)
                      : const Color(0xFF1d9bf0),
                ),
                recognizer: _track(
                  TapGestureRecognizer()
                    ..onTap = () {
                      final url = text.substring(match.start, match.end);
                      launchUrl(Uri.parse(url));
                    },
                ),
              ),
            );

            lastEnd = match.end;
          }

          if (lastEnd < text.length) {
            spans.add(
              TextSpan(
                text: text.substring(lastEnd),
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
              ),
            );
          }

          formattedCom.add(
            Text.rich(
              TextSpan(children: spans),
              style: const TextStyle(fontSize: 14, height: 1.35),
            ),
          );
        }
      }
    }

    return formattedCom;
  }

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
