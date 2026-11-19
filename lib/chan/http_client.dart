import 'package:flutter/foundation.dart';
import 'package:flutter_chan/chan/file_server_limit.dart';
import 'package:http/http.dart';

final Client _client = ArchiveAgentClient(TimeoutClient(Client()));

/// One client for every 4chan request, so they reuse the keep-alive
/// connections to a.4cdn.org and i.4cdn.org instead of opening new ones.
/// Full-size files wait while 4chan limits them ([FileServerLimit]).
final Client httpClient = FileServerClient(_client);

/// For images in view: while 4chan limits full-size files, these fail at
/// once instead of waiting, so the thumbnail shows instead of a spinner.
final Client imageClient = FileServerClient(_client, waitWhileLimited: false);

/// Names the app to the thread archives and their image servers, which turn
/// away Dart's own name; 4chan's requests go as they always have.
@visibleForTesting
class ArchiveAgentClient extends BaseClient {
  ArchiveAgentClient(this._inner);

  final Client _inner;

  static bool _isFourChan(String host) =>
      host == '4cdn.org' ||
      host.endsWith('.4cdn.org') ||
      host == '4chan.org' ||
      host.endsWith('.4chan.org');

  @override
  Future<StreamedResponse> send(BaseRequest request) {
    if (!_isFourChan(request.url.host)) {
      request.headers.putIfAbsent('User-Agent', () => 'NekoSurf');
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

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
