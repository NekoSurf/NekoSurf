import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/chan/post_text.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/ui/dash_menu.dart';
import 'package:flutter_chan/ui/toast.dart';
import 'package:provider/provider.dart';

/// Anchored long-press menu that turns a thread's title or comment into a
/// hidden-thread filter. Comments are truncated to keep patterns readable —
/// reposts share the same prefix, so a substring still catches them. Patterns
/// are escaped: a title containing '?', '|' or '(…)' must match literally,
/// not act as regex.
void showThreadFilterMenu(BuildContext context, Post post) {
  final settings = Provider.of<SettingsProvider>(context, listen: false);
  final String title = plainText(post.sub ?? '').trim();
  final String comment = plainText(post.com ?? '').trim();

  if (title.isEmpty && comment.isEmpty) {
    return;
  }

  void add(String text) {
    settings.addHiddenThreadPattern(RegExp.escape(text));
    showToast(context, 'Thread filter added');
  }

  final bool commentTruncated = comment.characters.length > 80;
  final String commentPrefix = comment.characters.take(80).toString();

  showDashMenu(
    context,
    title: 'Hide threads matching…',
    entries: [
      if (title.isNotEmpty)
        DashMenuEntry(
          title: 'Title: $title',
          icon: CupertinoIcons.eye_slash,
          onPressed: () => add(title),
        ),
      if (comment.isNotEmpty)
        DashMenuEntry(
          title: 'Comment: $commentPrefix${commentTruncated ? '…' : ''}',
          icon: CupertinoIcons.eye_slash,
          onPressed: () => add(commentPrefix),
        ),
    ],
  );
}
