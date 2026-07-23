import 'package:flutter/material.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SpoilerText extends ConsumerStatefulWidget {
  const SpoilerText({
    Key? key,
    required this.text,
  }) : super(key: key);

  final String text;

  @override
  ConsumerState<SpoilerText> createState() => _SpoilerTextState();
}

class _SpoilerTextState extends ConsumerState<SpoilerText> {
  bool _isRevealed = false;

  void _toggleReveal() {
    setState(() {
      _isRevealed = !_isRevealed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final isDark = theme == ThemeData.dark();

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
