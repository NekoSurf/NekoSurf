import 'package:flutter_chan/chan/load_errors.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/chan/urls.dart' as urls;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Post', () {
    test('parses 4chan JSON and tells what is attached', () {
      final Post video = Post.fromJson(const {
        'no': 42,
        'tim': 1700000000000,
        'ext': '.webm',
        'w': 1280,
        'h': 720,
        'tn_w': 250,
        'tn_h': 140,
      }, 'g');
      expect(video.no, 42);
      expect(video.tnW, 250);
      expect(video.hasFile, isTrue);
      expect(video.isVideo, isTrue);

      expect(Post(board: 'g', no: 1, tim: 1, ext: '.MP4').isVideo, isTrue);
      expect(Post(board: 'g', no: 1, tim: 1, ext: '.png').isVideo, isFalse);
      expect(Post(board: 'g', no: 1).hasFile, isFalse);
    });
  });

  test('urls', () {
    expect(urls.catalog('g').toString(), 'https://a.4cdn.org/g/catalog.json');
    expect(
      urls.thread('g', 123).toString(),
      'https://a.4cdn.org/g/thread/123.json',
    );
    expect(
      urls.file('wsg', 1700000000000, '.webm'),
      'https://i.4cdn.org/wsg/1700000000000.webm',
    );
    expect(
      urls.thumbnail('wsg', 1700000000000),
      'https://i.4cdn.org/wsg/1700000000000s.jpg',
    );
    expect(urls.threadPage('g', 123), 'https://boards.4chan.org/g/thread/123');
  });

  test('ApiException tells the status in its message', () {
    expect(const ApiException(503, 'catalog').toString(), contains('503'));
  });
}
