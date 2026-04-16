import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:provider/provider.dart';

class FloatingActionButtons extends StatelessWidget {
  const FloatingActionButtons({
    Key? key,
    this.scrollController,
    this.goUp,
    this.goDown,
  }) : super(key: key);

  final ScrollController? scrollController;
  final VoidCallback? goUp;
  final VoidCallback? goDown;

  void animateToTop() {
    scrollController!.animateTo(
      scrollController!.position.minScrollExtent,
      duration: const Duration(milliseconds: 400),
      curve: Curves.fastOutSlowIn,
    );
  }

  void animateToBottom() {
    scrollController!.animateTo(
      scrollController!.position.maxScrollExtent,
      duration: const Duration(milliseconds: 500),
      curve: Curves.fastOutSlowIn,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeChanger theme = Provider.of<ThemeChanger>(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FloatingActionButton(
          child: const Icon(Icons.expand_less, size: 35),
          elevation: 0,
          backgroundColor: theme.getTheme() == ThemeData.light()
              ? CupertinoColors.systemGroupedBackground.withValues(alpha: 0.7)
              : CupertinoColors.black.withOpacity(0.7),
          foregroundColor: CupertinoColors.activeBlue,
          onPressed: () => {if (goUp == null) animateToTop() else goUp!()},
          heroTag: null,
        ),
        const SizedBox(height: 40),
        FloatingActionButton(
          child: const Icon(Icons.expand_more, size: 35),
          elevation: 0,
          backgroundColor: theme.getTheme() == ThemeData.light()
              ? CupertinoColors.systemGroupedBackground.withValues(alpha: 0.7)
              : CupertinoColors.black.withOpacity(0.7),
          foregroundColor: CupertinoColors.activeBlue,
          onPressed: () => {
            if (goDown == null) animateToBottom() else goDown!(),
          },
          heroTag: null,
        ),
      ],
    );
  }
}
