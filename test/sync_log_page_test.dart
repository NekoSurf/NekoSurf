import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chan/settings/sync_log_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const MethodChannel channel = MethodChannel('nekosurf/cloudsync');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets("shows the Swift side's log, and says why when it can't", (
    tester,
  ) async {
    String? log = 'Engine: running\n\nNewest last:\nBatch: 1 saved file(s)';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          if (call.method != 'log') {
            return null;
          }
          if (log == null) {
            throw PlatformException(code: 'notEntitled');
          }
          return log;
        });

    await tester.pumpWidget(const MaterialApp(home: SyncLogPage()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Batch: 1 saved file(s)'), findsOneWidget);
    expect(find.bySemanticsLabel('Share'), findsOneWidget);

    log = null;
    await tester.pumpWidget(
      const MaterialApp(home: SyncLogPage(key: ValueKey('again'))),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining("can't use iCloud"), findsOneWidget);
  });
}
