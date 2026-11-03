import 'dart:io';

import 'package:flutter_chan/API/save_videos.dart';
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
      shareInTurn(ShareParams(text: 'a')),
      shareInTurn(ShareParams(text: 'b')),
      shareInTurn(ShareParams(text: 'c')),
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

    await expectLater(shareInTurn(ShareParams(text: 'a')), throwsStateError);
    await shareInTurn(ShareParams(text: 'b'));

    expect(opened, ['a', 'b']);
  });
}
