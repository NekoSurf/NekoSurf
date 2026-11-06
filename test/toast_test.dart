import 'package:flutter/material.dart';
import 'package:flutter_chan/ui/toast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a toast shows without blocking taps, then goes away', (
    tester,
  ) async {
    int taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {
                  taps++;
                  showToast(context, 'Saved');
                },
                child: const Text('Go'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Go'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Saved'), findsOneWidget);

    await tester.tap(find.text('Go'));
    await tester.pump();
    expect(taps, 2);
    expect(find.text('Saved'), findsOneWidget);

    // Fade in, stay, fade out.
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.text('Saved'), findsNothing);
  });
}
