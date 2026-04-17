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
          child: const Icon(Icons.keyboard_arrow_up_rounded, size: 28),
          elevation: 0,
          backgroundColor: theme.getTheme() == ThemeData.light()
              ? Colors.white.withValues(alpha: 0.92)
              : const Color(0xFF171A20).withValues(alpha: 0.92),
          foregroundColor: CupertinoColors.activeBlue,
          onPressed: () => {if (goUp == null) animateToTop() else goUp!()},
          heroTag: null,
        ),
        const SizedBox(height: 14),
        FloatingActionButton(
          child: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
          elevation: 0,
          backgroundColor: theme.getTheme() == ThemeData.light()
              ? Colors.white.withValues(alpha: 0.92)
              : const Color(0xFF171A20).withValues(alpha: 0.92),
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
