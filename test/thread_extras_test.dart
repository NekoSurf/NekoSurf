import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/API/archived.dart';
import 'package:flutter_chan/API/http_client.dart';
import 'package:flutter_chan/Models/bookmark_status.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  http.Response Function(http.BaseRequest request) answer = (_) =>
      http.Response('[]', 200);

  setUpAll(() {
    // httpClient is made on first use, here, around this one.
    http.runWithClient(
      () => httpClient,
      () => MockClient((http.Request request) async => answer(request)),
    );
  });

  group('the status of a bookmark', () {
    // A thread that's not in the catalog, so the thread itself is asked.
    void threadAnswers(int status) {
      answer = (http.BaseRequest request) =>
          request.url.path.contains('/thread/')
          ? http.Response('{"posts":[{"no":1,"replies":3}]}', status)
          : http.Response('[]', 200);
    }

    test('is deleted when 4chan says it does not have it', () async {
      threadAnswers(404);
      final BookmarkStatus status = await fetchBookmarkStatus('a', '1');
      expect(status.status, ThreadStatus.deleted);
    });

    test('is unknown when 4chan is limiting requests or failing', () async {
      threadAnswers(429);
      await expectLater(
        fetchBookmarkStatus('b', '1'),
        throwsA(isA<ApiException>()),
      );
      threadAnswers(500);
      await expectLater(
        fetchBookmarkStatus('c', '1'),
        throwsA(isA<ApiException>()),
      );
    });

    test('is online when it is there', () async {
      threadAnswers(200);
      final BookmarkStatus status = await fetchBookmarkStatus('d', '1');
      expect(status.status, ThreadStatus.online);
      expect(status.replies?.replies, 3);
    });
  });
}
