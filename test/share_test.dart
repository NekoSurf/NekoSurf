import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_chan/saved/give_media.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('share_test');
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  test("shares getting ready at once keep each other's files", () async {
    final Directory first = await newShareFolderIn(temp);
    File('${first.path}/cat.mp4').writeAsStringSync('cat');
    final Directory second = await newShareFolderIn(temp);

    expect(File('${first.path}/cat.mp4').readAsStringSync(), 'cat');
    expect(second.existsSync(), isTrue);
    finishShareFolder(first);
    finishShareFolder(second);
  });

  test('a finished share is kept until the next one starts', () async {
    final Directory done = await newShareFolderIn(temp);
    final Directory open = await newShareFolderIn(temp);
    finishShareFolder(done);
    expect(done.existsSync(), isTrue);

    final Directory next = await newShareFolderIn(temp);

    expect(done.existsSync(), isFalse);
    expect(open.existsSync(), isTrue);
    expect(next.existsSync(), isTrue);
    finishShareFolder(open);
    finishShareFolder(next);
  });

  test('what older versions left loose in the share folder goes', () async {
    final File loose = File('${temp.path}/shared/old.mp4')
      ..createSync(recursive: true);

    final Directory folder = await newShareFolderIn(temp);

    expect(loose.existsSync(), isFalse);
    finishShareFolder(folder);
  });

  test('share sheets open one after another', () async {
    final List<String> events = <String>[];
    showShareSheet = (ShareParams params) async {
      events.add('open ${params.text}');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      events.add('close ${params.text}');
    };

    await Future.wait([
      shareInTurn(null, (_) => ShareParams(text: 'a')),
      shareInTurn(null, (_) => ShareParams(text: 'b')),
      shareInTurn(null, (_) => ShareParams(text: 'c')),
    ]);

    expect(events, [
      'open a',
      'close a',
      'open b',
      'close b',
      'open c',
      'close c',
    ]);
  });

  test("a share sheet that fails doesn't hold up the next", () async {
    final List<String> opened = <String>[];
    showShareSheet = (ShareParams params) async {
      opened.add(params.text!);
      if (params.text == 'a') {
        throw StateError('no sheet');
      }
    };

    await expectLater(
      shareInTurn(null, (_) => ShareParams(text: 'a')),
      throwsStateError,
    );
    await shareInTurn(null, (_) => ShareParams(text: 'b'));

    expect(opened, ['a', 'b']);
  });

  group('a share sheet points', () {
    // The test window is 800 × 600.
    Future<BuildContext> button(WidgetTester tester, Offset at) async {
      late BuildContext button;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              Positioned(
                left: at.dx,
                top: at.dy,
                width: 40,
                height: 40,
                child: Builder(
                  builder: (context) {
                    button = context;
                    return const SizedBox.expand();
                  },
                ),
              ),
            ],
          ),
        ),
      );
      return button;
    }

    testWidgets('from the button that asked', (tester) async {
      final ShareAnchor anchor = ShareAnchor(
        await button(tester, const Offset(700, 20)),
      );

      expect(anchor.origin, const Rect.fromLTWH(700, 20, 40, 40));
    });

    testWidgets('only at the part of the button in the window', (tester) async {
      final ShareAnchor anchor = ShareAnchor(
        await button(tester, const Offset(780, 20)),
      );

      expect(anchor.origin, const Rect.fromLTWH(780, 20, 20, 40));
    });

    testWidgets('from the middle once the button is gone', (tester) async {
      final ShareAnchor anchor = ShareAnchor(
        await button(tester, const Offset(700, 20)),
      );
      await tester.pumpWidget(const SizedBox());

      expect(
        anchor.origin,
        Rect.fromCenter(center: const Offset(400, 300), width: 1, height: 1),
      );
    });

    testWidgets('from the middle when the button is off screen', (
      tester,
    ) async {
      final ShareAnchor anchor = ShareAnchor(
        await button(tester, const Offset(900, 20)),
      );

      expect(anchor.origin.center, const Offset(400, 300));
    });
  });

  test('a share sheet opens with where it points from', () async {
    Rect? pointsFrom;
    showShareSheet = (ShareParams params) async {
      pointsFrom = params.sharePositionOrigin;
    };

    await shareInTurn(
      null,
      (Rect origin) => ShareParams(text: 'a', sharePositionOrigin: origin),
    );

    expect(pointsFrom, isNotNull);
    expect(pointsFrom!.isEmpty, isFalse);
  });
}
