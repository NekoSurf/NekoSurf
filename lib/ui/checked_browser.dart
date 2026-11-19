import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Whether [body] is Cloudflare's "checking your browser" page rather than
/// the page that was asked for.
bool isCloudflareChallenge(String body) {
  final String lower = body.toLowerCase();
  return lower.contains('challenges.cloudflare.com') ||
      lower.contains('cf-chl') ||
      lower.contains('challenge-platform') ||
      lower.contains('<title>just a moment');
}

/// Why [CheckedBrowser.load] gave nothing back.
class CheckedBrowserFailed implements Exception {
  const CheckedBrowserFailed(this.reason);

  final String reason;

  @override
  String toString() => 'CheckedBrowserFailed: $reason';
}

/// Loads pages of a site behind Cloudflare in a web view, and reads them.
///
/// A plain HTTP request only gets Cloudflare's challenge page; a web view
/// runs the challenge like a browser and keeps the clearance cookie for the
/// next pages. When the challenge doesn't pass on its own, [verifying] turns
/// true and [CheckedBrowserLayer] shows the web view so the user can
/// complete it; the page is read once they have.
///
/// The [controller]'s web view must stay in the widget tree while a page
/// loads, even when hidden, or iOS may not run the challenge's scripts.
class CheckedBrowser extends ChangeNotifier {
  CheckedBrowser() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _inspect(),
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              _finish(error: CheckedBrowserFailed(error.description));
            }
          },
        ),
      );
  }

  late final WebViewController controller;

  /// How long a challenge gets to pass on its own before the user is asked.
  static const Duration _challengeGrace = Duration(seconds: 4);

  /// How long a page may take while the user isn't busy verifying.
  static const Duration _timeout = Duration(seconds: 25);

  Completer<Object?>? _pending;
  FutureOr<Object?> Function(String html)? _read;
  Timer? _challengeTimer;
  Timer? _timeoutTimer;
  bool _disposed = false;

  bool _verifying = false;
  bool get verifying => _verifying;

  /// [url], as [read] makes it out of the page's HTML. [read] answers null
  /// for a page that isn't the one asked for, such as the challenge.
  Future<T> load<T extends Object>(
    Uri url,
    FutureOr<T?> Function(String html) read,
  ) async {
    _finish(error: const CheckedBrowserFailed('Replaced by a new page'));

    final Completer<Object?> completer = Completer();
    _pending = completer;
    _read = read;
    _timeoutTimer = Timer(
      _timeout,
      () => _finish(error: const CheckedBrowserFailed('Timed out')),
    );
    controller.loadRequest(url);
    return (await completer.future)! as T;
  }

  /// Gives up on the page loading, e.g. when the user closes the check.
  void cancel() {
    _finish(error: const CheckedBrowserFailed('Cancelled'));
  }

  Future<void> _inspect() async {
    final Completer<Object?>? pending = _pending;
    final FutureOr<Object?> Function(String html)? read = _read;
    if (pending == null || read == null) {
      return;
    }

    String html;
    try {
      final Object result = await controller.runJavaScriptReturningResult(
        'document.documentElement.outerHTML',
      );
      html = result is String ? result : '$result';
      // Android hands strings back JSON-encoded.
      if (html.startsWith('"')) {
        html = jsonDecode(html) as String;
      }
    } catch (_) {
      return;
    }

    if (_pending != pending) {
      return;
    }

    // Read first: Cloudflare also injects its scripts into real pages.
    Object? page;
    try {
      page = await read(html);
    } catch (_) {
      page = null;
    }
    if (_pending != pending) {
      return;
    }
    if (page != null) {
      _finish(page: page);
    } else if (isCloudflareChallenge(html)) {
      // Most challenges pass by themselves and reload into the page.
      _challengeTimer ??= Timer(_challengeGrace, _askToVerify);
    } else {
      _finish(error: const CheckedBrowserFailed('Unrecognized response'));
    }
  }

  void _askToVerify() {
    if (_pending == null || _verifying) {
      return;
    }
    // The user takes as long as they need.
    _timeoutTimer?.cancel();
    _setVerifying(true);
  }

  void _finish({Object? page, Object? error}) {
    final Completer<Object?>? pending = _pending;
    _pending = null;
    _read = null;
    _challengeTimer?.cancel();
    _challengeTimer = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _setVerifying(false);

    if (pending == null || pending.isCompleted) {
      return;
    }
    if (page != null) {
      pending.complete(page);
    } else {
      pending.completeError(error ?? const CheckedBrowserFailed('Failed'));
    }
  }

  void _setVerifying(bool value) {
    if (_verifying == value) {
      return;
    }
    _verifying = value;
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}

/// [child] with [browser]'s web view over it: a hidden pixel while a page
/// loads, a card over [child] while the user completes a Cloudflare check,
/// headed by [title]. The tree keeps the same shape either way, so the web
/// view isn't recreated.
class CheckedBrowserLayer extends StatelessWidget {
  const CheckedBrowserLayer({
    super.key,
    required this.browser,
    required this.title,
    required this.child,
  });

  final CheckedBrowser? browser;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final CheckedBrowser? browser = this.browser;
    if (browser == null) {
      return child;
    }
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: ListenableBuilder(
            listenable: browser,
            builder: (context, webView) => _layer(context, browser, webView!),
            child: WebViewWidget(controller: browser.controller),
          ),
        ),
      ],
    );
  }

  Widget _layer(BuildContext context, CheckedBrowser browser, Widget webView) {
    final bool verifying = browser.verifying;
    final EdgeInsets safe = MediaQuery.paddingOf(context);

    return Stack(
      children: [
        IgnorePointer(
          ignoring: !verifying,
          child: ColoredBox(
            color: verifying ? Colors.black54 : Colors.transparent,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: verifying ? 12 : 0,
          top: verifying ? safe.top + 60 : 0,
          right: verifying ? 12 : null,
          bottom: verifying ? safe.bottom + 24 : null,
          width: verifying ? null : 1,
          height: verifying ? null : 1,
          child: IgnorePointer(
            ignoring: !verifying,
            // Not 0: a fully transparent web view isn't painted at all, and
            // iOS then stops running its scripts.
            child: Opacity(
              opacity: verifying ? 1 : 0.01,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: ColoredBox(
                  color: DashColors.card(context),
                  child: Column(
                    children: [
                      Visibility(
                        visible: verifying,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: DashColors.text(context),
                                  ),
                                ),
                              ),
                              CupertinoButton(
                                onPressed: browser.cancel,
                                child: const Text('Cancel'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(child: webView),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
