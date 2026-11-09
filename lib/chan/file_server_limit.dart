import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart';

/// Whether [url] is a full-size file on 4chan's file server (i.4cdn.org):
/// a video or image, not its thumbnail (`<tim>s.jpg`).
bool isFullFile(Uri url) =>
    url.host == 'i.4cdn.org' && !url.path.endsWith('s.jpg');

/// 4chan's file server answers too many requests with 429 ("too many
/// requests"), and then refuses full-size files for a while, minutes at a
/// time; thumbnails and threads still load.
///
/// Asking again only keeps it going: with every video on screen and the
/// preloads retrying on their own, the app hammered it for as long as it
/// lasted. So once a request is refused, every full-size file waits here
/// ([ready]), and one request at a time checks whether it has let up: after
/// 10 s, then ever less often, at most every 2 minutes. The first one let
/// through lifts it for all.
class FileServerLimit extends ChangeNotifier {
  @visibleForTesting
  FileServerLimit({
    this.firstWait = const Duration(seconds: 10),
    this.longestWait = const Duration(minutes: 2),
  });

  static final FileServerLimit instance = FileServerLimit();

  final Duration firstWait;
  final Duration longestWait;

  Duration _wait = Duration.zero;
  // While limited: when the next check may go out.
  DateTime? _until;
  // Counts the limits so far; an answer to a request sent before the
  // current one started says nothing about it.
  int _limits = 0;
  // A request checking whether it has let up; the others wait for it.
  Completer<void>? _checking;

  /// Whether 4chan refuses full-size files right now.
  bool get limited => _until != null;

  /// Returns once a request for a full-size file may go out, with what to
  /// tell [answered] or [unanswered] about it.
  Future<FileServerTicket> ready() async {
    while (true) {
      final DateTime? until = _until;
      if (until == null) {
        return FileServerTicket._(_limits, check: false);
      }
      final Completer<void>? checking = _checking;
      if (checking != null) {
        await checking.future;
        continue;
      }
      final Duration left = until.difference(DateTime.now());
      if (left > Duration.zero) {
        await Future<void>.delayed(left);
        continue;
      }
      _checking = Completer<void>();
      return FileServerTicket._(_limits, check: true);
    }
  }

  /// A request [ready] let out with [ticket] got [status] back.
  void answered(FileServerTicket ticket, int status) {
    final bool current = ticket._limits == _limits;
    if (status == 429) {
      // Several in flight when it started are all refused: they count as
      // one, and only a refused check waits longer.
      if (!limited || current) {
        _wait = _wait == Duration.zero
            ? firstWait
            : Duration(
                microseconds: min(
                  _wait.inMicroseconds * 2,
                  longestWait.inMicroseconds,
                ),
              );
        final bool was = limited;
        if (!was) {
          _limits++;
        }
        _until = DateTime.now().add(_wait);
        if (!was) {
          notifyListeners();
        }
      }
    } else if (limited && current) {
      _until = null;
      _wait = Duration.zero;
      notifyListeners();
    } else if (!limited) {
      _wait = Duration.zero;
    }
    _endCheck(ticket);
  }

  /// A request [ready] let out with [ticket] got no answer (the connection
  /// failed).
  void unanswered(FileServerTicket ticket) => _endCheck(ticket);

  void _endCheck(FileServerTicket ticket) {
    if (!ticket._check) {
      return;
    }
    final Completer<void>? checking = _checking;
    _checking = null;
    checking?.complete();
  }
}

/// What [FileServerLimit.ready] let a request out as.
class FileServerTicket {
  FileServerTicket._(this._limits, {required bool check}) : _check = check;

  // How many limits there had been when it went out.
  final int _limits;
  // Checking whether 4chan has let up.
  final bool _check;
}

/// Sends full-size files from 4chan through [FileServerLimit]: while it's
/// limited, a request waits for its turn, or with [waitWhileLimited] off
/// fails at once ([FileServerLimitedException]) without asking at all.
class FileServerClient extends BaseClient {
  FileServerClient(
    this._inner, {
    this.waitWhileLimited = true,
    FileServerLimit? limit,
    this.isLimited = isFullFile,
  }) : _limit = limit ?? FileServerLimit.instance;

  final Client _inner;
  final FileServerLimit _limit;
  final bool waitWhileLimited;
  final bool Function(Uri url) isLimited;

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    if (!isLimited(request.url)) {
      return _inner.send(request);
    }
    if (!waitWhileLimited && _limit.limited) {
      throw FileServerLimitedException(request.url);
    }
    final FileServerTicket ticket = await _limit.ready();
    final StreamedResponse response;
    try {
      response = await _inner.send(request);
    } catch (_) {
      _limit.unanswered(ticket);
      rethrow;
    }
    _limit.answered(ticket, response.statusCode);
    return response;
  }

  @override
  void close() => _inner.close();
}

/// 4chan refuses full-size files for now (see [FileServerLimit]).
class FileServerLimitedException extends HttpException {
  FileServerLimitedException(Uri url)
    : super('4chan is limiting downloads', uri: url);
}
