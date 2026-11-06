import 'package:flutter/foundation.dart';
import 'package:http/http.dart';

/// One client for every 4chan API call, so requests reuse the keep-alive
/// connection to a.4cdn.org instead of opening a new one each time.
final Client httpClient = TimeoutClient(Client());

/// Gives up on a connection that goes quiet, rather than leaving whoever asked
/// waiting until the system does: [stall] without an answer, or without more of
/// it. Big downloads aren't limited, as long as they keep arriving.
@visibleForTesting
class TimeoutClient extends BaseClient {
  TimeoutClient(this._inner, {this.stall = const Duration(seconds: 20)});

  final Client _inner;
  final Duration stall;

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final StreamedResponse response = await _inner.send(request).timeout(stall);
    return StreamedResponse(
      response.stream.timeout(stall),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
