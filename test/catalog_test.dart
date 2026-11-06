import 'package:flutter_chan/chan/catalog.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_test/flutter_test.dart';

List<int?> _numbers(Iterable<Post> posts) => [for (final p in posts) p.no];

void main() {
  group('sortThreads', () {
    final List<Post> threads = [
      Post(board: 'g', no: 1, replies: 5, time: 300),
      Post(board: 'g', no: 2, replies: 50, time: 100),
      Post(board: 'g', no: 3, replies: 1, time: 200, sticky: 1),
      Post(board: 'g', no: 4, replies: 20, time: 400),
    ];

    test('sorts by the chosen key', () {
      expect(
        _numbers(sortThreads(threads, Sort.byReplyCount, SortDirection.desc)),
        [2, 4, 1, 3],
      );
      expect(
        _numbers(sortThreads(threads, Sort.byReplyCount, SortDirection.asc)),
        [3, 1, 4, 2],
      );
      expect(
        _numbers(sortThreads(threads, Sort.byNewest, SortDirection.desc)),
        [4, 1, 3, 2],
      );
    });

    test('can put stickies first, keeping the order', () {
      expect(
        _numbers(
          stickyFirst(
            sortThreads(threads, Sort.byReplyCount, SortDirection.desc),
          ),
        ),
        [3, 2, 4, 1],
      );
    });

    test('leaves the original list alone', () {
      sortThreads(threads, Sort.byReplyCount, SortDirection.desc);
      expect(_numbers(threads), [1, 2, 3, 4]);
    });
  });

  group('filterThreads', () {
    final List<Post> threads = [
      Post(board: 'g', no: 1, sub: 'Linux general', com: 'Post your desktops'),
      Post(board: 'g', no: 2, com: 'Tea &amp; <b>biscuits</b>'),
      Post(board: 'g', no: 3, name: 'linus', com: 'Nothing here'),
    ];

    test('needs every word, in any order and any case', () {
      expect(_numbers(filterThreads(threads, 'DESKTOPS linux')), [1]);
      expect(_numbers(filterThreads(threads, 'linux windows')), isEmpty);
    });

    test('searches the text without markup or escapes', () {
      expect(_numbers(filterThreads(threads, 'tea & biscuits')), [2]);
    });

    test('matches the poster name, and everything for an empty query', () {
      expect(_numbers(filterThreads(threads, 'linus')), [3]);
      expect(filterThreads(threads, '  '), threads);
    });
  });
}
