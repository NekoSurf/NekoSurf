import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/constants.dart';
import 'package:provider/provider.dart';

class ReloadWidget extends StatefulWidget {
  const ReloadWidget({Key? key, required this.onReload}) : super(key: key);

  final Function() onReload;

  @override
  State<ReloadWidget> createState() => _ReloadWidgetState();
}

class _ReloadWidgetState extends State<ReloadWidget> {
  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeChanger>(context);
    final bool isDark = theme.getTheme() == ThemeData.dark();

    return Container(
      color: AppColors.pageBackground(isDark),
      child: SizedBox(
        height: 400,
        child: CupertinoButton(
          onPressed: widget.onReload,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(CupertinoIcons.arrow_counterclockwise),
              const SizedBox(width: 8),
              Text(
                'Loading failed',
                style: TextStyle(
                  fontSize: 18,
                  color: theme.getTheme() == ThemeData.dark()
                      ? CupertinoColors.white
                      : CupertinoColors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
