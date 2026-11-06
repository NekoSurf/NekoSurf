import 'package:flutter/material.dart';
import 'package:flutter_chan/ui/colors.dart';

class SpoilerText extends StatefulWidget {
  const SpoilerText({super.key, required this.text});

  final String text;

  @override
  State<SpoilerText> createState() => _SpoilerTextState();
}

class _SpoilerTextState extends State<SpoilerText> {
  bool _isRevealed = false;

  void _toggleReveal() {
    setState(() {
      _isRevealed = !_isRevealed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;

    return GestureDetector(
      onTap: _toggleReveal,
      child: Text(
        widget.text,
        style: TextStyle(
          color: _isRevealed
              ? (isDark ? Colors.black : Colors.white)
              : (isDark ? Colors.white : Colors.black),
          backgroundColor: isDark ? Colors.white : Colors.black,
        ),
      ),
    );
  }
}
