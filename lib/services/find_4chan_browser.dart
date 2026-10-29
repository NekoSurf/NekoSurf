import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_chan/API/global_search.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Loads find.4chan.org in a web view and reads the results out of it.
///
/// A plain HTTP request only gets Cloudflare's challenge page; a web view
/// runs the challenge like a browser and keeps the clearance cookie for
/// later searches. When the challenge doesn't pass on its own, [verifying]
/// turns true and the web view has to be shown so the user can complete
/// it; results arrive once they have.
///
/// The [controller]'s web view must stay in the widget tree while a search
/// runs, even when hidden, or iOS may not run the challenge's scripts.
class Find4chanBrowser extends ChangeNotifier {
  Find4chanBrowser() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _inspect(),
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              _finish(error: GlobalSearchUnavailable(error.description));
            }
          },
        ),
      );
  }

  late final WebViewController controller;

  /// How long a challenge gets to pass on its own before the user is asked.
  static const Duration _challengeGrace = Duration(seconds: 4);

  /// How long a search may take while the user isn't busy verifying.
  static const Duration _timeout = Duration(seconds: 25);

  Completer<GlobalSearchPage>? _pending;
  int _offset = 0;
  Timer? _challengeTimer;
  Timer? _timeoutTimer;
  bool _disposed = false;

  bool _verifying = false;
  bool get verifying => _verifying;

  Future<GlobalSearchPage> search(String query, {int offset = 0}) {
    _finish(error: const GlobalSearchUnavailable('Replaced by a new search'));

    final Completer<GlobalSearchPage> completer = Completer();
    _pending = completer;
    _offset = offset;
    _timeoutTimer = Timer(
      _timeout,
      () => _finish(error: const GlobalSearchUnavailable('Timed out')),
    );
    controller.loadRequest(globalSearchUri(query, offset: offset));
    return completer.future;
  }

  /// Gives up on the running search, e.g. when the user closes the check.
  void cancel() {
    _finish(error: const GlobalSearchUnavailable('Cancelled'));
  }

  Future<void> _inspect() async {
    final Completer<GlobalSearchPage>? pending = _pending;
    if (pending == null) {
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

    // Parse first: Cloudflare also injects its scripts into real pages.
    final GlobalSearchPage? page = await parseGlobalSearchPageInBackground(
      html,
      offset: _offset,
    );
    if (_pending != pending) {
      return;
    }
    if (page != null) {
      _finish(page: page);
    } else if (isCloudflareChallenge(html)) {
      // Most challenges pass by themselves and reload into the results.
      _challengeTimer ??= Timer(_challengeGrace, _askToVerify);
    } else {
      _finish(error: const GlobalSearchUnavailable('Unrecognized response'));
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

  void _finish({GlobalSearchPage? page, Object? error}) {
    final Completer<GlobalSearchPage>? pending = _pending;
    _pending = null;
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
      pending.completeError(error ?? const GlobalSearchUnavailable('Failed'));
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
