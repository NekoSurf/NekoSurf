import 'dart:io';

import 'package:flutter_chan/API/save_videos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('saved_file_name_test');
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  test('saves of same-named uploads at once each get a name', () async {
    File('${dir.path}/cat.mp4').writeAsStringSync('');

    final List<String?> names = await Future.wait([
      for (int i = 0; i < 3; i++)
        uniqueSavedFileName(dir.path, 'cat.webm', '.mp4', reserve: true),
    ]);

    expect(names, ['cat (2).mp4', 'cat (3).mp4', 'cat (4).mp4']);
  });

  test('a reserved name is free again once released', () async {
    final String? first = await uniqueSavedFileName(
      dir.path,
      'cat.webm',
      '.mp4',
      reserve: true,
    );
    expect(first, 'cat.mp4');
    expect(
      await uniqueSavedFileName(dir.path, 'cat.webm', '.mp4'),
      'cat (2).mp4',
    );

    releaseSavedFileName(dir.path, first!);
    expect(await uniqueSavedFileName(dir.path, 'cat.webm', '.mp4'), 'cat.mp4');
  });

  test('only a reserving save holds on to the name', () async {
    expect(await uniqueSavedFileName(dir.path, 'cat.webm', '.mp4'), 'cat.mp4');
    expect(await uniqueSavedFileName(dir.path, 'cat.webm', '.mp4'), 'cat.mp4');
  });
}
