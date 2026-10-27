import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';

/// "5 new posts ↓" pill shown when a live thread update adds posts.
class NewPostsPill extends StatefulWidget {
  const NewPostsPill({Key? key, required this.count, required this.onTap})
    : super(key: key);

  final int count;
  final VoidCallback onTap;

  @override
  State<NewPostsPill> createState() => _NewPostsPillState();
}

class _NewPostsPillState extends State<NewPostsPill> {
  // Keeps showing the last count while the pill fades out, instead of
  // "0 new posts".
  late int _shownCount = widget.count;

  @override
  void didUpdateWidget(covariant NewPostsPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count > 0) {
      _shownCount = widget.count;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool visible = widget.count > 0;
    final int count = _shownCount;

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 0.5),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: DashColors.accent,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    count == 1 ? '1 new post' : '$count new posts',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    CupertinoIcons.arrow_down,
                    size: 16,
                    color: Colors.black,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
