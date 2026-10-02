import 'package:flutter/material.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:provider/provider.dart';

class SpoilerText extends StatefulWidget {
  const SpoilerText({Key? key, required this.text}) : super(key: key);

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
    final theme = Provider.of<ThemeChanger>(context);
    final isDark = theme.getTheme() == ThemeData.dark();

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
