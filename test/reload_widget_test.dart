import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/widgets/reload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  Future<void> showError(WidgetTester tester, Object? error) {
    return tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeChanger(ThemeData.dark()),
        child: CupertinoApp(
          home: ReloadWidget.forError(error, onReload: () {}),
        ),
      ),
    );
  }

  testWidgets('says why loading failed', (tester) async {
    await showError(tester, const ApiException(429, 'catalog'));
    expect(find.text('Too many requests'), findsOneWidget);

    await showError(tester, const ApiException(404, 'thread'));
    expect(find.text('Not found'), findsOneWidget);

    await showError(tester, const ApiException(503, 'board list'));
    expect(find.text('4chan is having trouble'), findsOneWidget);

    await showError(tester, const SocketException('No route to host'));
    expect(find.text('Loading failed'), findsOneWidget);
  });
}
