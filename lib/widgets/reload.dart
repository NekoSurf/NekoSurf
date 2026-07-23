import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/constants.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReloadWidget extends ConsumerWidget {
  const ReloadWidget({Key? key, required this.onReload}) : super(key: key);

  final Function() onReload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final bool isDark = theme == ThemeData.dark();

    return Container(
      color: AppColors.pageBackground(isDark),
      child: SizedBox(
        height: 400,
        child: CupertinoButton(
          onPressed: onReload,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(CupertinoIcons.arrow_counterclockwise),
              const SizedBox(width: 8),
              Text(
                'Loading failed',
                style: TextStyle(
                  fontSize: 18,
                  color: isDark
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
