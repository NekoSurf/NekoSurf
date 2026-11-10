import 'package:flutter/material.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/frosted.dart';

OverlayEntry? _current;

/// A short message at the bottom of the screen, gone after a moment. It sits
/// above the page without taking taps, so the screen stays usable under it.
void showToast(BuildContext context, String message) {
  _current?.remove();
  final OverlayState overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _Toast(
      message: message,
      onDone: () {
        entry.remove();
        entry.dispose();
        if (_current == entry) {
          _current = null;
        }
      },
    ),
  );
  _current = entry;
  overlay.insert(entry);
}

class _Toast extends StatefulWidget {
  const _Toast({required this.message, required this.onDone});

  final String message;
  final VoidCallback onDone;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  static const Duration _shown = Duration(milliseconds: 1800);

  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await _fade.forward();
    await Future<void>.delayed(_shown);
    if (!mounted) {
      return;
    }
    await _fade.reverse();
    if (mounted) {
      widget.onDone();
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 96,
              left: 24,
              right: 24,
            ),
            child: Frosted(
              fade: _fade,
              radius: 999,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              color: Frosted.panel(context),
              borderColor: context.accent.withValues(alpha: 0.25),
              child: FadeTransition(
                opacity: _fade,
                child: Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DashColors.text(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
