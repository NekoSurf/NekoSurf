import 'dart:io';

import 'package:flutter_chan/services/image_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('image_cache_size');
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  void create(String path, int bytes) => File('${temp.path}/$path')
    ..createSync(recursive: true)
    ..writeAsBytesSync(List.filled(bytes, 0));

  test('adds up both image caches and nothing else', () async {
    create('thumbnail_cache/456s.jpg', 300);
    create('thumbnail_cache/789s.jpg', 200);
    create('image_cache/456.png', 1000);
    // Not image caches.
    create('shared/123.webm', 5000);
    create('libCachedImageData/0f1e.mp4', 7000);

    expect(await imageCacheSizeIn(temp), 1500);
  });

  test('is 0 before anything is cached', () async {
    expect(await imageCacheSizeIn(temp), 0);
  });
}
