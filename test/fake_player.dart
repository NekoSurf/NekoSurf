import 'dart:async';

import 'package:flutter_chan/media/video_players.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// A media_kit [Player] that plays nothing. It records what it's asked to
/// do in [calls], keeps [state] as mpv would, and lets the test say what mpv
/// reports ([decode], [emitPosition], [reachEnd], ...).
///
/// Its streams are broadcast and asynchronous, like media_kit's: what it
/// emits arrives once microtasks run (a `tester.pump()`).
class FakePlayer implements Player {
  FakePlayer(this.calls);

  /// What it was asked to do, in order: `open <uri>` (with ` at <ms>ms` for a
  /// start), `play`, `pause`, `stop`, `seek <ms>ms`, `volume <n>`,
  /// `rate <x>`, `playlistMode <name>`, `dispose`. Shared with its output,
  /// which adds `setSize <w>x<h>`.
  final List<String> calls;

  /// Every [Media] it opened, in order.
  final List<Media> opened = <Media>[];

  /// Every seek's target, in order.
  final List<Duration> seeks = <Duration>[];

  bool disposed = false;

  /// While set, [open] waits for it to complete.
  Completer<void>? openGate;

  /// While true, each [seek] waits for [finishSeek].
  bool holdSeeks = false;
  final List<Completer<void>> _pendingSeeks = <Completer<void>>[];

  int get pendingSeeks => _pendingSeeks.length;

  /// Lets the oldest held seek finish.
  void finishSeek() => _pendingSeeks.removeAt(0).complete();

  PlayerState _state = const PlayerState();

  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  final StreamController<bool> _completed = StreamController<bool>.broadcast();
  final StreamController<Duration> _position =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _duration =
      StreamController<Duration>.broadcast();
  final StreamController<double> _volume = StreamController<double>.broadcast();
  final StreamController<double> _rate = StreamController<double>.broadcast();
  final StreamController<bool> _buffering = StreamController<bool>.broadcast();
  final StreamController<PlaylistMode> _playlistMode =
      StreamController<PlaylistMode>.broadcast();
  final StreamController<VideoParams> _videoParams =
      StreamController<VideoParams>.broadcast();
  final StreamController<String> _error = StreamController<String>.broadcast();

  @override
  PlayerState get state => _state;

  @override
  late final PlayerStream stream = PlayerStream(
    const Stream<Playlist>.empty(),
    _playing.stream,
    _completed.stream,
    _position.stream,
    _duration.stream,
    _volume.stream,
    _rate.stream,
    const Stream<double>.empty(),
    _buffering.stream,
    const Stream<double>.empty(),
    const Stream<Duration>.empty(),
    _playlistMode.stream,
    const Stream<bool>.empty(),
    const Stream<AudioParams>.empty(),
    _videoParams.stream,
    const Stream<double?>.empty(),
    const Stream<AudioDevice>.empty(),
    const Stream<List<AudioDevice>>.empty(),
    const Stream<Track>.empty(),
    const Stream<Tracks>.empty(),
    const Stream<int?>.empty(),
    const Stream<int?>.empty(),
    const Stream<List<String>>.empty(),
    const Stream<PlayerLog>.empty(),
    _error.stream,
  );

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    final Media media = playable as Media;
    final Duration? start = media.start;
    calls.add(
      'open ${media.uri}${start == null ? '' : ' at ${start.inMilliseconds}ms'}',
    );
    opened.add(media);
    final Completer<void>? gate = openGate;
    if (gate != null) {
      await gate.future;
    }
    _state = _state.copyWith(
      position: start ?? Duration.zero,
      completed: false,
    );
    _position.add(_state.position);
    _completed.add(false);
    _setPlaying(play);
  }

  @override
  Future<void> play() async {
    calls.add('play');
    _setPlaying(true);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _setPlaying(false);
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    _state = _state.copyWith(
      playing: false,
      completed: false,
      position: Duration.zero,
      duration: Duration.zero,
    );
    _playing.add(false);
    _completed.add(false);
    _position.add(Duration.zero);
    _duration.add(Duration.zero);
  }

  @override
  Future<void> seek(Duration duration) async {
    calls.add('seek ${duration.inMilliseconds}ms');
    seeks.add(duration);
    if (holdSeeks) {
      final Completer<void> done = Completer<void>();
      _pendingSeeks.add(done);
      await done.future;
    }
    // Seeking back from the end leaves it, as mpv's eof-reached does.
    _state = _state.copyWith(position: duration, completed: false);
    _position.add(duration);
    _completed.add(false);
  }

  @override
  Future<void> setVolume(double volume) async {
    calls.add('volume ${volume.round()}');
    _state = _state.copyWith(volume: volume);
    _volume.add(volume);
  }

  @override
  Future<void> setRate(double rate) async {
    calls.add('rate $rate');
    _state = _state.copyWith(rate: rate);
    _rate.add(rate);
  }

  @override
  Future<void> setPlaylistMode(PlaylistMode playlistMode) async {
    calls.add('playlistMode ${playlistMode.name}');
    _state = _state.copyWith(playlistMode: playlistMode);
    _playlistMode.add(playlistMode);
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    disposed = true;
  }

  void _setPlaying(bool playing) {
    _state = _state.copyWith(playing: playing);
    _playing.add(playing);
  }

  /// mpv decoded the video's first frame, of [width] x [height].
  void decode({int width = 640, int height = 360}) =>
      emitVideoParams(VideoParams(w: width, h: height, dw: width, dh: height));

  void emitVideoParams(VideoParams params) {
    _state = _state.copyWith(videoParams: params);
    _videoParams.add(params);
  }

  void emitPlaying(bool playing) => _setPlaying(playing);

  void emitPosition(Duration position) {
    _state = _state.copyWith(position: position);
    _position.add(position);
  }

  void emitDuration(Duration duration) {
    _state = _state.copyWith(duration: duration);
    _duration.add(duration);
  }

  void emitBuffering(bool buffering) {
    _state = _state.copyWith(buffering: buffering);
    _buffering.add(buffering);
  }

  void emitCompleted(bool completed) {
    _state = _state.copyWith(completed: completed);
    _completed.add(completed);
  }

  /// Plays to the end without looping: mpv stops at the last frame and says
  /// it completed.
  void reachEnd() {
    _state = _state.copyWith(
      position: _state.duration,
      playing: false,
      completed: true,
    );
    _position.add(_state.position);
    _playing.add(false);
    _completed.add(true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Views aren't under test: nothing on it is used.
class FakeVideoController implements VideoController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A [PlayerOutput] around a [FakePlayer], made at [width] x [height] (null
/// when not sized up front). The test fires mpv's playback restarts
/// ([restart]) and the output's own first frame ([reportFirstFrame]).
class FakeOutput implements PlayerOutput {
  FakeOutput({this.width, this.height});

  final int? width;
  final int? height;

  /// The size it was made at.
  (int?, int?) get size => (width, height);

  /// What its player and it were asked to do (see [FakePlayer.calls]).
  final List<String> calls = <String>[];

  @override
  late final FakePlayer player = FakePlayer(calls);

  @override
  final VideoController controller = FakeVideoController();

  /// Every size it was given after it was made.
  final List<(int?, int?)> sizes = <(int?, int?)>[];

  bool get disposed => player.disposed;

  void Function()? _onRestart;
  final Completer<void> _firstFrame = Completer<void>();

  @override
  Future<void> listenForRestarts(void Function() onRestart) {
    _onRestart = onRestart;
    return Future<void>.value();
  }

  /// mpv restarted playback (it drew the first frame after an open or seek).
  void restart() => _onRestart?.call();

  @override
  Future<void> get firstFrame => _firstFrame.future;

  /// The output's own first frame, which it reports once, for its first
  /// video.
  void reportFirstFrame() {
    if (!_firstFrame.isCompleted) {
      _firstFrame.complete();
    }
  }

  /// Shows the video opened in it, whichever way its lease waits for that:
  /// the output's own first frame, and mpv's decoded frame and restart.
  void showFirstFrame({int width = 640, int height = 360}) {
    reportFirstFrame();
    player.decode(width: width, height: height);
    restart();
  }

  @override
  Future<void> setSize(int? width, int? height) async {
    calls.add('setSize ${width}x$height');
    sizes.add((width, height));
  }

  @override
  Future<void> dispose() => player.dispose();
}

/// Makes [FakeOutput]s for a VideoPlayers, keeping each it made.
class FakeOutputs {
  final List<FakeOutput> created = <FakeOutput>[];

  PlayerOutput create({int? width, int? height}) {
    final FakeOutput output = FakeOutput(width: width, height: height);
    created.add(output);
    return output;
  }
}
