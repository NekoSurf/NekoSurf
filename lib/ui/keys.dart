import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// [key] with ⌘ (an iPad's keyboard) or Ctrl (an Android tablet's).
List<SingleActivator> withCommand(
  LogicalKeyboardKey key, {
  bool shift = false,
}) => [
  SingleActivator(key, meta: true, shift: shift),
  SingleActivator(key, control: true, shift: shift),
];

/// [bindings], each for every activator its key list holds.
Map<ShortcutActivator, VoidCallback> keyBindings(
  Map<List<ShortcutActivator>, VoidCallback> bindings,
) => {
  for (final MapEntry<List<ShortcutActivator>, VoidCallback> binding
      in bindings.entries)
    for (final ShortcutActivator activator in binding.key)
      activator: binding.value,
};

/// A hardware keyboard's shortcuts for a page, while it's the one in front:
/// it takes the keyboard's focus when it's shown, and keys a page doesn't
/// use go on to the app's (see [AppKeys]).
class PageKeys extends StatelessWidget {
  const PageKeys({super.key, required this.bindings, required this.child});

  final Map<ShortcutActivator, VoidCallback> bindings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(autofocus: true, child: child),
    );
  }
}

/// The shortcuts every page has: Esc, ⌘W or ⌘[ go back, as the back icon
/// does, from the pane in front first. In a text field, Esc leaves it.
class AppKeys extends StatelessWidget {
  const AppKeys({super.key, required this.child});

  final Widget child;

  static void goBack() {
    final FocusNode? focus = FocusManager.instance.primaryFocus;
    final BuildContext? context = focus?.context;
    if (focus == null || context == null) {
      return;
    }
    if (context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null) {
      focus.unfocus();
      return;
    }
    // The innermost navigator that has something to go back to: a pane's,
    // then the app's.
    NavigatorState? navigator = Navigator.maybeOf(context);
    while (navigator != null && !navigator.canPop()) {
      navigator = navigator.context.findAncestorStateOfType<NavigatorState>();
    }
    navigator?.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: keyBindings({
        [const SingleActivator(LogicalKeyboardKey.escape)]: goBack,
        withCommand(LogicalKeyboardKey.keyW): goBack,
        withCommand(LogicalKeyboardKey.bracketLeft): goBack,
      }),
      child: child,
    );
  }
}
