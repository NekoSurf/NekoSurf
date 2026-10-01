import 'package:flutter/cupertino.dart';

Future<dynamic> showCupertinoSnackbar(
  Duration? duration,
  bool dismissable,
  BuildContext context,
  String message,
) {
  return showCupertinoDialog(
    context: context,
    builder: (context) {
      if (duration != null) {
        Future.delayed(duration, () {
          Navigator.of(context).pop(true);
        });
      }
      return GestureDetector(
        onTap: () {
          if (dismissable) {
            Navigator.of(context).pop(true);
          }
        },
        child: CupertinoAlertDialog(title: Text(message)),
      );
    },
  );
}
