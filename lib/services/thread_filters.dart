import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/services/show_snackbar.dart';
import 'package:flutter_chan/services/string.dart';
import 'package:flutter_chan/widgets/dash_dialogs.dart';
import 'package:provider/provider.dart';

/// Anchored long-press menu that turns a thread's title or comment into a
/// hidden-thread filter. Comments are truncated to keep patterns readable —
/// reposts share the same prefix, so a substring still catches them.
void showThreadFilterMenu(BuildContext context, Post post) {
  final settings = Provider.of<SettingsProvider>(context, listen: false);
  final String title = unescape(cleanTags(post.sub ?? '')).trim();
  final String comment = unescape(cleanTags(post.com ?? '')).trim();

  if (title.isEmpty && comment.isEmpty) {
    return;
  }

  void add(String pattern) {
    settings.addHiddenThreadPattern(pattern);
    showCupertinoSnackbar(
      const Duration(seconds: 2),
      true,
      context,
      'Thread filter added',
    );
  }

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
          title:
              'Comment: ${comment.length > 60 ? '${comment.substring(0, 60)}…' : comment}',
          icon: CupertinoIcons.eye_slash,
          onPressed: () => add(
            comment.length > 80 ? comment.substring(0, 80) : comment,
          ),
        ),
    ],
  );
}
