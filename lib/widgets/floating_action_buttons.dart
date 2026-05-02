import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/utils/build_blur_pill.dart';

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
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        GestureDetector(
          onTap: () => {if (goUp == null) animateToTop() else goUp!()},
          child: buildBlurPill(
            child: const Icon(
              Icons.keyboard_arrow_up_rounded,
              size: 28,
              color: CupertinoColors.white,
            ),
            padding: const EdgeInsets.all(8),
          ),
        ),
        const SizedBox(height: 14),

        GestureDetector(
          onTap: () => {if (goDown == null) animateToBottom() else goDown!()},
          child: buildBlurPill(
            child: const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 28,
              color: CupertinoColors.white,
            ),
            padding: const EdgeInsets.all(8),
          ),
        ),
      ],
    );
  }
}
