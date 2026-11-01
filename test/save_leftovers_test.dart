import 'dart:io';

import 'package:flutter_chan/API/save_videos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('save_leftovers_test');
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  void create(String path) => File('${temp.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync('x');

  List<String> remaining() => [
    for (final FileSystemEntity entity in temp.listSync())
      entity.path.split('/').last,
  ]..sort();

  test('deletes what saving and sharing left, and nothing else', () async {
    // Left by older versions, right in the temporary directory.
    create('Some Opening.webm');
    create('Some Opening.mp4');
    create('cat.JPG');
    // Left by a share, and by a save that never finished.
    create('shared/Some Opening.mp4');
    create('working/abc123/clip.webm');
    // Not ours to delete.
    create('video_cache/123.webm');
    create('thumbnail_cache/456s.jpg');
    create('flutter_callback_cache.json');

    await deleteSaveLeftoversIn(temp);

    expect(remaining(), [
      'flutter_callback_cache.json',
      'thumbnail_cache',
      'video_cache',
    ]);
    expect(File('${temp.path}/video_cache/123.webm').existsSync(), isTrue);
  });
}
