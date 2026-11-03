import 'package:flutter/widgets.dart';

/// Takes the focus off a text field when a page opens over it.
///
/// A page remembers which of its fields had focus, and focuses it again
/// when it's back on top; so a thread opened while typing in a search field
/// brought the keyboard up again on coming back. Unfocusing it while it
/// still has focus makes the page forget it.
///
/// Only pages: a field still has its keyboard after a dialog or a sheet.
class UnfocusOnPushObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute) {
      return;
    }
    final FocusNode? focus = FocusManager.instance.primaryFocus;
    final BuildContext? context = focus?.context;
    if (context == null ||
        context.findAncestorStateOfType<EditableTextState>() == null) {
      return;
    }
    focus!.unfocus();
  }
}
