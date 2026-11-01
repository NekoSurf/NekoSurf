import 'dart:io';

import 'package:flutter_chan/services/image_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late Directory support;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('old_image_cache_temp');
    support = Directory.systemTemp.createTempSync('old_image_cache_support');
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
    support.deleteSync(recursive: true);
  });

  void create(Directory dir, String path) => File('${dir.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync('x');

  List<String> remaining(Directory dir) => [
    for (final FileSystemEntity entity in dir.listSync())
      entity.path.split('/').last,
  ]..sort();

  test('deletes the old default cache and keeps the current ones', () async {
    create(temp, 'libCachedImageData/0f1e.mp4');
    create(support, 'libCachedImageData.db');
    create(support, 'libCachedImageData.db-journal');
    // The caches in use.
    create(temp, 'thumbnail_cache/456s.jpg');
    create(temp, 'image_cache/456.png');
    create(support, 'thumbnail_cache.db');
    create(support, 'image_cache.db');
    create(support, 'savedThumbnails/1.jpg');

    await deleteOldImageCacheIn(temp, support);

    expect(remaining(temp), ['image_cache', 'thumbnail_cache']);
    expect(remaining(support), [
      'image_cache.db',
      'savedThumbnails',
      'thumbnail_cache.db',
    ]);
  });

  test('does nothing when there is no old cache', () async {
    create(temp, 'thumbnail_cache/456s.jpg');

    await deleteOldImageCacheIn(temp, support);

    expect(remaining(temp), ['thumbnail_cache']);
  });
}
