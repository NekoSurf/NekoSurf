import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/pages/thread/thread_replied_to.dart';
import 'package:flutter_chan/services/string.dart';
import 'package:flutter_chan/widgets/spoiler_text.dart';
import 'package:html/parser.dart' show parse;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class ThreadPostComment extends StatelessWidget {
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

  List<Widget> formatComment(
    String com,
    ThemeChanger theme,
    BuildContext context,
  ) {
    final theme = Provider.of<ThemeChanger>(context);
    final isDark = theme.getTheme() == ThemeData.dark();

    final List<Widget> formattedCom = [];

    final List<String> splittedCom = com.split('<br>');

    for (final line in splittedCom) {
      if (line.startsWith('<a href')) {
        final document = parse(line);

        final urlNo = document.body!.text.replaceFirst('>>', '');

        formattedCom.add(
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ThreadRepliesTo(
                    post: int.parse(urlNo),
                    thread: thread,
                    board: board,
                    allPosts: allPosts,
                  ),
                ),
              );
            },
            child: Text(
              '>> $urlNo',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: CupertinoColors.activeBlue,
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
        final RegExp spoilerPattern = RegExp(r'<s>(.*?)</s>');
        final String remainingText = line;
        int lastEnd = 0;

        for (final match in spoilerPattern.allMatches(line)) {
          // Add non-spoiler text before the match
          if (match.start > lastEnd) {
            final normalText = unescape(
              cleanTags(remainingText.substring(lastEnd, match.start)),
            );
            spans.add(
              TextSpan(
                text: normalText,
                style: TextStyle(
                  color: theme.getTheme() == ThemeData.dark()
                      ? Colors.white
                      : Colors.black,
                ),
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
              style: TextStyle(
                color: theme.getTheme() == ThemeData.dark()
                    ? Colors.white
                    : Colors.black,
              ),
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
        final RegExp urlPattern = RegExp(
          r'https?://[\w-]+(\.[\w-]+)+([\w.,@?^=%&:/~+#-]*[\w@?^=%&/~+#-])?',
          caseSensitive: false,
        );

        final text = unescape(cleanTags(line));
        final matches = urlPattern.allMatches(text);

        if (matches.isEmpty) {
          formattedCom.add(
            SelectableText(
              text,
              style: TextStyle(
                color: theme.getTheme() == ThemeData.dark()
                    ? Colors.white
                    : Colors.black,
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
                  style: TextStyle(
                    color: theme.getTheme() == ThemeData.dark()
                        ? Colors.white
                        : Colors.black,
                  ),
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
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    final url = text.substring(match.start, match.end);
                    launchUrl(Uri.parse(url));
                  },
              ),
            );

            lastEnd = match.end;
          }

          if (lastEnd < text.length) {
            spans.add(
              TextSpan(
                text: text.substring(lastEnd),
                style: TextStyle(
                  color: theme.getTheme() == ThemeData.dark()
                      ? Colors.white
                      : Colors.black,
                ),
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

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeChanger>(context);

    final List<Widget> listCom = formatComment(com, theme, context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final Widget comments in listCom) comments],
    );
  }
}
