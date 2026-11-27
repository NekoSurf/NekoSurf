import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every board's text colour, in [brightness].
Future<Map<String, Color>> _colors(
  WidgetTester tester,
  Brightness brightness,
) async {
  final Map<String, Color> colors = {};
  await tester.pumpWidget(
    CupertinoApp(
      theme: CupertinoThemeData(brightness: brightness),
      home: Builder(
        builder: (context) {
          // Enough codes to land on every colour of the palette.
          for (final String board in ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']) {
            colors[board] = boardTextColor(context, board);
          }
          return const SizedBox();
        },
      ),
    ),
  );
  return colors;
}

double _contrastOnWhite(Color color) =>
    1.05 / (color.computeLuminance() + 0.05);

void main() {
  testWidgets('in the light, board codes read on white', (tester) async {
    final Map<String, Color> colors = await _colors(tester, Brightness.light);
    for (final MapEntry<String, Color> board in colors.entries) {
      expect(
        _contrastOnWhite(board.value),
        greaterThanOrEqualTo(4.5),
        reason: '/${board.key}/',
      );
    }
  });

  testWidgets('in the dark, they keep the palette as it is', (tester) async {
    final Map<String, Color> colors = await _colors(tester, Brightness.dark);
    for (final MapEntry<String, Color> board in colors.entries) {
      expect(board.value, boardColor(board.key));
    }
  });
}
