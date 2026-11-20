import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats file sizes', () {
    expect(formatFileSize(640 * 1024), '640 KB');
    expect(formatFileSize(1300000), '1.2 MB');
  });

  test('a post describes its file', () {
    final Post post = Post.fromJson(<String, dynamic>{
      'no': 1,
      'tim': 1700000000000,
      'ext': '.webm',
      'fsize': 1300000,
      'w': 1920,
      'h': 1080,
    }, 'wg');
    expect(post.fileDetails, '1.2 MB · 1920×1080 · WEBM');
    expect(Post.fromJson(post.toJson(), 'wg').fsize, 1300000);
  });

  test('a post without a file has no details', () {
    expect(Post(board: 'g', no: 1).fileDetails, isNull);
  });
}
