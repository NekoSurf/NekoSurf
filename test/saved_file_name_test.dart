import 'dart:convert';
import 'dart:io';

import 'package:flutter_chan/saved/saved_folders.dart';
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

    // In any order: which save's file check comes back first varies.
    expect(
      names,
      unorderedEquals(['cat (2).mp4', 'cat (3).mp4', 'cat (4).mp4']),
    );
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

  test('a long Japanese name fits the file system, uncut', () async {
    final String long = '${'猫' * 120}.webm';

    final String? name = await uniqueSavedFileName(dir.path, long, '.mp4');
    File('${dir.path}/$name').writeAsStringSync('');
    final String? second = await uniqueSavedFileName(dir.path, long, '.mp4');

    expect(utf8.encode(second!).length, lessThanOrEqualTo(255));
    expect(name, startsWith('猫'));
    File('${dir.path}/$second').writeAsStringSync('');
  });

  test('names are clipped between characters, not inside one', () async {
    final String? name = await uniqueSavedFileName(
      dir.path,
      '${'😺' * 80}.webm',
      '.mp4',
    );

    expect(name, matches(RegExp(r'^(😺)+\.mp4$')));
    expect(utf8.encode(name!).length, lessThanOrEqualTo(255));
  });

  test('a downloaded file is named like the upload, made safe', () {
    expect(localFileName('cat.webm'), 'cat.webm');
    expect(localFileName('cat/dog.webm'), 'cat_dog.webm');
    // Not hidden, and nowhere but its folder.
    expect(localFileName('../dog.webm'), 'file.webm');
    expect(localFileName('.webm'), 'file.webm');
    expect(localFileName('   .webm'), 'file.webm');
    final String long = localFileName('${'猫' * 120}.webm');
    expect(long, endsWith('.webm'));
    expect(utf8.encode(long).length, lessThanOrEqualTo(255));
    File('${dir.path}/$long').writeAsStringSync('');
  });

  test('only a reserving save holds on to the name', () async {
    expect(await uniqueSavedFileName(dir.path, 'cat.webm', '.mp4'), 'cat.mp4');
    expect(await uniqueSavedFileName(dir.path, 'cat.webm', '.mp4'), 'cat.mp4');
  });
}
