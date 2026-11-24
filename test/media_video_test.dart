import 'package:flutter/widgets.dart';
import 'package:flutter_chan/media/media_video.dart';
import 'package:flutter_chan/media/video_players.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player.dart';

// Each test's videos have sources of their own: MediaVideo keeps videos and
// found sizes by source, app-wide.
int _sources = 0;

/// Fake players for the videos a test obtains ([obtain]), which [end]
/// releases, so no timer is left behind.
class _Videos {
  _Videos({bool sizesUpFront = false}) {
    players = VideoPlayers(
      create: outputs.create,
      sizesUpFront: sizesUpFront,
      reuses: true,
    );
    // Videos take the players there are as they're made.
    VideoPlayers.instance = players;
    addTearDown(() async {
      if (_ended) {
        return;
      }
      // A test that failed midway.
      for (final MediaVideo video in _held.reversed.toList()) {
        video.release(_nobody);
      }
      await Future<void>.delayed(Duration.zero);
      players.dispose();
    });
  }

  static const Object _nobody = Object();

  final FakeOutputs outputs = FakeOutputs();
  late final VideoPlayers players;
  // One for each time a video was obtained and not yet released.
  final List<MediaVideo> _held = <MediaVideo>[];
  bool _ended = false;

  /// A video on the phone, new to this test.
  MediaVideo obtain(String name, {int? width, int? height}) =>
      again('/videos/${_sources++}-$name.webm', width: width, height: height);

  MediaVideo again(String source, {int? width, int? height}) {
    final MediaVideo video = MediaVideo.obtain(
      source,
      width: width,
      height: height,
    );
    _held.add(video);
    return video;
  }

  void release(MediaVideo video, Object owner) {
    _held.remove(video);
    video.release(owner);
  }

  /// The output whose player has [video] open.
  FakeOutput outputOf(MediaVideo video) => outputs.created.lastWhere(
    (FakeOutput output) =>
        output.player.opened.isNotEmpty &&
        output.player.opened.last.uri == video.source,
  );

  Future<void> end(WidgetTester tester) async {
    _ended = true;
    for (final MediaVideo video in _held.reversed.toList()) {
      video.release(_nobody);
    }
    _held.clear();
    await tester.pump();
    players.dispose();
  }
}

/// Lets what's started run: opening (a reused player sized up front waits
/// for a frame) and the player's events.
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 3; i++) {
    await tester.pump();
  }
}

/// What [output] was asked to do since [mark] calls.
List<String> _since(FakeOutput output, int mark) => output.calls.sublist(mark);

const Duration _s3 = Duration(seconds: 3);
const Duration _s10 = Duration(seconds: 10);

void main() {
  testWidgets('the same source is one video', (tester) async {
    final _Videos videos = _Videos();
    final MediaVideo a = videos.obtain('a');
    final MediaVideo again = videos.again(a.source);
    expect(again, same(a));

    // Still held once.
    videos.release(again, 'viewer');
    final MediaVideo third = videos.again(a.source);
    expect(third, same(a));

    videos.release(third, 'viewer');
    videos.release(a, 'post');
    final MediaVideo fresh = videos.again(a.source);
    expect(fresh, isNot(same(a)));
    await videos.end(tester);
  });

  testWidgets('wanting it starts and plays it', (tester) async {
    final _Videos videos = _Videos();
    final MediaVideo video = videos.obtain('a');
    expect(videos.outputs.created, isEmpty);

    video.want('post');
    await _settle(tester);
    final FakeOutput output = videos.outputs.created.single;
    expect(output.calls, <String>[
      'volume 0',
      'rate 1.0',
      'playlistMode single',
      'open ${video.source}',
      'play',
    ]);
    // The video starts at the top.
    expect(output.player.opened.single.start, isNull);
    expect(video.isPlaying, isTrue);
    expect(video.isLoading, isTrue);
    expect(video.hasFirstFrame, isFalse);
    expect(video.controller, same(output.controller));

    output.showFirstFrame();
    await _settle(tester);
    expect(video.hasFirstFrame, isTrue);
    expect(video.isLoading, isFalse);
    await videos.end(tester);
  });

  testWidgets('unwanted, it frees its player at once and pauses after a '
      'moment', (tester) async {
    final _Videos videos = _Videos();
    final List<MediaVideo> four = <MediaVideo>[
      for (final String name in <String>['a', 'b', 'c', 'd'])
        videos.obtain(name),
    ];
    for (final MediaVideo video in four) {
      video.want('post');
    }
    await _settle(tester);
    for (final MediaVideo video in four) {
      videos.outputOf(video).showFirstFrame();
    }
    await _settle(tester);
    expect(videos.players.canAcquire(0.5), isFalse);

    final MediaVideo a = four[0];
    final FakePlayer player = videos.outputOf(a).player;
    a.unwant('post');
    // Another video may take it right away...
    expect(videos.players.canAcquire(0.5), isTrue);
    // ...but it plays on meanwhile.
    await tester.pump(const Duration(milliseconds: 249));
    expect(player.state.playing, isTrue);
    expect(a.isPlaying, isTrue);
    await tester.pump(const Duration(milliseconds: 1));
    expect(player.calls.last, 'pause');
    expect(player.state.playing, isFalse);
    expect(a.isPlaying, isFalse);

    // Wanted again within the moment, it doesn't pause.
    final MediaVideo b = four[1];
    final FakeOutput bOutput = videos.outputOf(b);
    final int mark = bOutput.calls.length;
    b.unwant('post');
    await tester.pump(const Duration(milliseconds: 100));
    b.want('post');
    await tester.pump(const Duration(milliseconds: 500));
    expect(_since(bOutput, mark), isNot(contains('pause')));
    expect(b.isPlaying, isTrue);
    await videos.end(tester);
  });

  testWidgets('is heard while someone wants it audible, or it is unmuted', (
    tester,
  ) async {
    final _Videos videos = _Videos();
    final MediaVideo video = videos.obtain('a');
    video.want('post');
    await _settle(tester);
    final FakePlayer player = videos.outputOf(video).player;
    expect(player.state.volume, 0);

    video.want('viewer', audible: true);
    expect(player.state.volume, 100);
    video.unwant('viewer');
    expect(player.state.volume, 0);

    video.muted = false;
    expect(player.state.volume, 100);
    video.muted = true;
    expect(player.state.volume, 0);

    // Opened for someone who wants sound, it starts with it.
    final MediaVideo loud = videos.obtain('loud');
    loud.want('viewer', audible: true);
    await _settle(tester);
    expect(videos.outputOf(loud).calls.first, 'volume 100');
    await videos.end(tester);
  });

  testWidgets('a video that shows nothing is tried once more with a new '
      'player, then fails until retried', (tester) async {
    final _Videos videos = _Videos();
    final MediaVideo video = videos.obtain('a');
    video.want('post');
    await _settle(tester);
    final FakeOutput first = videos.outputs.created.single;
    expect(video.isLoading, isTrue);

    await tester.pump(const Duration(seconds: 9));
    expect(first.disposed, isFalse);
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    // Not kept for the next video: it may be what broke.
    expect(first.disposed, isTrue);
    expect(first.calls, isNot(contains('stop')));
    expect(videos.outputs.created, hasLength(2));
    final FakeOutput second = videos.outputs.created[1];
    expect(second.player.opened.single.uri, video.source);
    expect(video.failed, isFalse);
    expect(video.isLoading, isTrue);

    await tester.pump(_s10);
    await _settle(tester);
    expect(second.disposed, isTrue);
    expect(video.failed, isTrue);
    expect(video.isLoading, isFalse);
    expect(video.controller, isNull);

    // No more tries by itself.
    await tester.pump(const Duration(seconds: 30));
    expect(videos.outputs.created, hasLength(2));

    await video.retry();
    await _settle(tester);
    expect(video.failed, isFalse);
    expect(videos.outputs.created, hasLength(3));
    final FakeOutput third = videos.outputs.created[2];
    third.showFirstFrame();
    await _settle(tester);
    expect(video.hasFirstFrame, isTrue);
    expect(video.isPlaying, isTrue);
    await videos.end(tester);
  });

  testWidgets('its player taken after its first frame, it goes on later '
      'where it was', (tester) async {
    final _Videos videos = _Videos();
    final MediaVideo a = videos.obtain('a');
    a.want('post', shown: 0.5);
    await _settle(tester);
    final FakeOutput output = videos.outputOf(a);
    output.showFirstFrame();
    output.player.emitDuration(_s10);
    output.player.emitPosition(_s3);
    await _settle(tester);
    expect(a.position.value, _s3);

    for (final String name in <String>['b', 'c', 'd']) {
      videos.obtain(name).want('post');
    }
    await _settle(tester);
    // Shown clearly more than a.
    final MediaVideo e = videos.obtain('e');
    e.want('post');
    await _settle(tester);
    expect(videos.outputOf(e), same(output));
    expect(videos.outputs.created, hasLength(4));
    expect(a.hasFirstFrame, isFalse);
    expect(a.isPlaying, isFalse);
    expect(a.controller, isNull);

    final int mark = output.calls.length;
    videos.release(e, 'post');
    await _settle(tester);
    expect(videos.outputOf(a), same(output));
    expect(output.player.opened.last.start, _s3);
    expect(
      _since(output, mark),
      containsAllInOrder(<String>['open ${a.source} at 3000ms', 'play']),
    );
    output.showFirstFrame();
    await _settle(tester);
    expect(a.hasFirstFrame, isTrue);
    expect(a.isPlaying, isTrue);
    await videos.end(tester);
  });

  testWidgets('after the background it goes on where it was, unless the '
      'user paused it', (tester) async {
    final _Videos videos = _Videos();
    final MediaVideo playing = videos.obtain('playing');
    final MediaVideo paused = videos.obtain('paused');
    playing.want('post');
    paused.want('post');
    await _settle(tester);
    for (final MediaVideo video in <MediaVideo>[playing, paused]) {
      final FakeOutput output = videos.outputOf(video);
      output.showFirstFrame();
      output.player.emitDuration(_s10);
      output.player.emitPosition(_s3);
    }
    await _settle(tester);
    paused.togglePlay();
    await _settle(tester);
    expect(paused.isPlaying, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await _settle(tester);
    expect(playing.controller, isNull);
    expect(paused.controller, isNull);
    expect(videos.outputs.created.every((FakeOutput o) => o.disposed), isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    expect(videos.outputs.created, hasLength(4));
    final FakeOutput playingOutput = videos.outputOf(playing);
    final FakeOutput pausedOutput = videos.outputOf(paused);
    expect(playingOutput.disposed, isFalse);
    expect(playingOutput.player.opened.single.start, _s3);
    expect(pausedOutput.player.opened.single.start, _s3);
    expect(playingOutput.calls.last, 'play');
    expect(pausedOutput.calls, isNot(contains('play')));
    playingOutput.showFirstFrame();
    pausedOutput.showFirstFrame();
    await _settle(tester);
    expect(playing.isPlaying, isTrue);
    expect(paused.isPlaying, isFalse);
    expect(paused.hasFirstFrame, isTrue);
    await videos.end(tester);
  });

  group('scrubbing', () {
    testWidgets('pauses, seeks one at a time and ends at the last target', (
      tester,
    ) async {
      final _Videos videos = _Videos();
      final MediaVideo video = videos.obtain('a');
      video.want('post');
      await _settle(tester);
      final FakeOutput output = videos.outputOf(video);
      final FakePlayer player = output.player;
      output.showFirstFrame();
      player.emitDuration(_s10);
      player.emitPosition(const Duration(seconds: 4));
      await _settle(tester);
      expect(video.isPlaying, isTrue);

      player.holdSeeks = true;
      video.scrubStart();
      expect(player.calls.last, 'pause');
      expect(video.scrubPosition.value, const Duration(seconds: 4));

      video.scrubTo(const Duration(seconds: 1));
      video.scrubTo(const Duration(seconds: 2));
      video.scrubTo(_s3);
      expect(player.seeks, <Duration>[const Duration(seconds: 1)]);
      expect(video.shownPosition, _s3);

      player.finishSeek();
      await tester.pump();
      // Straight to where the finger is now, skipping 2 s.
      expect(player.seeks, <Duration>[const Duration(seconds: 1), _s3]);

      // Kept within the video.
      video.scrubTo(const Duration(seconds: 20));
      expect(video.scrubPosition.value, _s10);
      video.scrubTo(const Duration(seconds: -1));
      expect(video.scrubPosition.value, Duration.zero);
      video.scrubTo(const Duration(seconds: 5));
      player.finishSeek();
      await tester.pump();
      player.finishSeek();
      await tester.pump();
      expect(player.pendingSeeks, 0);
      expect(player.seeks, <Duration>[
        const Duration(seconds: 1),
        _s3,
        const Duration(seconds: 5),
      ]);
      // Paused all along.
      expect(player.state.playing, isFalse);

      player.holdSeeks = false;
      await video.scrubEnd();
      await _settle(tester);
      expect(player.seeks.last, const Duration(seconds: 5));
      expect(video.scrubPosition.value, isNull);
      expect(video.position.value, const Duration(seconds: 5));
      // It played before, so it plays on.
      expect(player.calls.last, 'play');
      expect(video.isPlaying, isTrue);
      await videos.end(tester);
    });
  });
}
