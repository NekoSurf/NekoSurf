import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/chan/load_errors.dart';
import 'package:flutter_chan/ui/reload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> showError(WidgetTester tester, Object? error) {
    return tester.pumpWidget(
      CupertinoApp(home: ReloadWidget.forError(error, onReload: () {})),
    );
  }

  testWidgets('says why loading failed', (tester) async {
    await showError(tester, const ApiException(429, 'catalog'));
    expect(find.text('Too many requests'), findsOneWidget);

    await showError(tester, const ApiException(404, 'thread'));
    expect(find.text('Not found'), findsOneWidget);

    await showError(tester, const ThreadNotFound());
    expect(find.text('Not found'), findsOneWidget);

    await showError(tester, const ApiException(503, 'board list'));
    expect(find.text('4chan is having trouble'), findsOneWidget);

    await showError(tester, const SocketException('No route to host'));
    expect(find.text('Loading failed'), findsOneWidget);
  });
}
