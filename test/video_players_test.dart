import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_chan/media/video_players.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'fake_player.dart';

/// VideoPlayers with fake outputs, disposed after the test.
VideoPlayers _players(
  FakeOutputs outputs, {
  bool sizesUpFront = false,
  bool reuses = true,
}) {
  final VideoPlayers players = VideoPlayers(
    create: outputs.create,
    sizesUpFront: sizesUpFront,
    reuses: reuses,
  );
  addTearDown(players.dispose);
  return players;
}

Future<void> _noSetUp(Player player) async {}

void main() {
  late FakeOutputs outputs;
  // Which holders were told their player was taken, in order.
  late List<String> evicted;

  setUp(() {
    outputs = FakeOutputs();
    evicted = <String>[];
  });

  VideoLease? take(
    VideoPlayers players,
    String name,
    double priority, {
    int? width,
    int? height,
  }) {
    return players.acquire(
      onEvicted: () => evicted.add(name),
      priority: priority,
      width: width,
      height: height,
    );
  }

  group('how many players', () {
    testWidgets(
      'makes at most four; a fifth video wanted about as much waits',
      (tester) async {
        final VideoPlayers players = _players(outputs);
        for (final String name in <String>['a', 'b', 'c', 'd']) {
          expect(take(players, name, 1), isNotNull);
        }
        expect(players.playerCount, 4);
        expect(outputs.created, hasLength(4));

        expect(players.canAcquire(1.2), isFalse);
        expect(take(players, 'e', 1.2), isNull);
        expect(players.playerCount, 4);
        expect(outputs.created, hasLength(4));
        expect(evicted, isEmpty);
        await tester.pump();
      },
    );

    testWidgets('a video wanted clearly more takes the least wanted player', (
      tester,
    ) async {
      final VideoPlayers players = _players(outputs);
      final VideoLease a = take(players, 'a', 1)!;
      final VideoLease b = take(players, 'b', 0.5)!;
      take(players, 'c', 0.8);
      take(players, 'd', 1);

      // 0.5 is wanted more than 0.25 less than 1: b goes.
      final VideoLease e = take(players, 'e', 1)!;
      expect(evicted, <String>['b']);
      expect(players.playerCount, 4);
      // Its player is stopped and handed over, not a new one made.
      expect(outputs.created, hasLength(4));
      expect(e.player, same(b.player));
      await tester.pump();
      expect(
        outputs.created[1].calls,
        containsAllInOrder(<String>['pause', 'stop']),
      );
      expect(outputs.created[1].disposed, isFalse);

      // The least wanted left (0.8) is about as wanted as another 1.
      expect(take(players, 'f', 1), isNull);
      expect(evicted, <String>['b']);
      expect(a.player, same(outputs.created[0].player));
    });

    testWidgets('unwanted players go first, least recently wanted first', (
      tester,
    ) async {
      final VideoPlayers players = _players(outputs);
      take(players, 'a', 1);
      final VideoLease b = take(players, 'b', 1)!;
      take(players, 'c', 1);
      final VideoLease d = take(players, 'd', 1)!;

      // b is wanted again after d was, then neither is.
      b.priority = 1;
      b.priority = 0;
      d.priority = 0;
      expect(b.wanted, isFalse);

      // Even a video wanted far less than the others takes an unwanted
      // player: d's, the one wanted longest ago.
      expect(take(players, 'e', 0.1), isNotNull);
      expect(evicted, <String>['d']);
      expect(take(players, 'f', 0.1), isNotNull);
      expect(evicted, <String>['d', 'b']);

      // None is unwanted now, and none wanted clearly less.
      expect(take(players, 'g', 0.1), isNull);
      expect(evicted, <String>['d', 'b']);
      await tester.pump();
    });

    testWidgets('tells a video that waits when a player is wanted less or '
        'freed', (tester) async {
      final VideoPlayers players = _players(outputs);
      int notified = 0;
      players.addListener(() => notified++);
      final VideoLease a = take(players, 'a', 1)!;
      final VideoLease b = take(players, 'b', 1)!;
      take(players, 'c', 1);
      take(players, 'd', 1);
      await tester.pump();
      notified = 0;

      expect(take(players, 'e', 1), isNull);
      a.priority = 0.6;
      await tester.pump();
      expect(notified, 1);

      // Nobody waits now.
      a.priority = 0.5;
      await tester.pump();
      expect(notified, 1);

      b.release();
      await tester.pump();
      expect(notified, 2);
      expect(take(players, 'e', 1), isNotNull);
      expect(evicted, isEmpty);
    });
  });

  group('giving players back', () {
    testWidgets('a released player is stopped and handed to the next video', (
      tester,
    ) async {
      final VideoPlayers players = _players(outputs);
      final VideoLease a = take(players, 'a', 1)!;
      await a.open(Media('/videos/a.webm'), setUp: _noSetUp);
      await a.player.play();
      a.release();
      await tester.pump();

      final FakeOutput output = outputs.created.single;
      expect(
        output.calls,
        containsAllInOrder(<String>['open /videos/a.webm', 'pause', 'stop']),
      );
      expect(output.disposed, isFalse);
      expect(players.playerCount, 1);

      final VideoLease b = take(players, 'b', 1)!;
      expect(b.player, same(output.player));
      expect(outputs.created, hasLength(1));
      expect(players.playerCount, 1);
      expect(await b.open(Media('/videos/b.webm'), setUp: _noSetUp), isTrue);
      expect(output.calls.last, 'open /videos/b.webm');
      expect(evicted, isEmpty);
    });

    testWidgets('without reuse, a released player is disposed', (tester) async {
      final VideoPlayers players = _players(outputs, reuses: false);
      final VideoLease a = take(players, 'a', 1)!;
      await a.open(Media('/videos/a.webm'), setUp: _noSetUp);
      a.release();
      await tester.pump();

      final FakeOutput output = outputs.created.single;
      expect(output.disposed, isTrue);
      // Paused first, to stop mpv's threads; not stopped for another video.
      expect(output.calls, containsAllInOrder(<String>['pause', 'dispose']));
      expect(output.calls, isNot(contains('stop')));
      expect(players.playerCount, 0);

      final VideoLease b = take(players, 'b', 1)!;
      expect(outputs.created, hasLength(2));
      expect(b.player, same(outputs.created[1].player));
    });

    testWidgets('a player that broke is disposed, not reused', (tester) async {
      final VideoPlayers players = _players(outputs);
      final VideoLease a = take(players, 'a', 1)!;
      await a.open(Media('/videos/a.webm'), setUp: _noSetUp);
      a.release(broke: true);
      await tester.pump();

      expect(outputs.created.single.disposed, isTrue);
      expect(players.playerCount, 0);
      take(players, 'b', 1);
      expect(outputs.created, hasLength(2));
    });

    testWidgets('open does nothing once its lease was given back before '
        'its turn', (tester) async {
      final VideoPlayers players = _players(outputs);
      final VideoLease a = take(players, 'a', 1)!;
      final FakeOutput output = outputs.created.single;
      final Completer<void> gate = Completer<void>();
      output.player.openGate = gate;
      final Future<bool> aOpened = a.open(
        Media('/videos/a.webm'),
        setUp: _noSetUp,
      );
      await tester.pump();
      // a is still opening its video as it gives the player back.
      a.release();

      final VideoLease b = take(players, 'b', 1)!;
      expect(b.player, same(a.player));
      bool bSetUp = false;
      final Future<bool> bOpened = b.open(
        Media('/videos/b.webm'),
        setUp: (_) async => bSetUp = true,
      );
      b.release();

      output.player.openGate = null;
      gate.complete();
      await tester.pump();
      expect(await aOpened, isTrue);
      expect(await bOpened, isFalse);
      expect(bSetUp, isFalse);
      expect(output.player.opened.map((Media m) => m.uri), <String>[
        '/videos/a.webm',
      ]);

      // Given back before it even asked: the same.
      final VideoLease c = take(players, 'c', 1)!..release();
      expect(await c.open(Media('/videos/c.webm'), setUp: _noSetUp), isFalse);
      expect(output.player.opened, hasLength(1));
      expect(output.disposed, isFalse);
    });
  });

  testWidgets('the background takes every player away until the app is '
      'shown again', (tester) async {
    final VideoPlayers players = _players(outputs);
    int notified = 0;
    players.addListener(() => notified++);
    take(players, 'a', 1);
    take(players, 'b', 0.5);
    final VideoLease c = take(players, 'c', 1)!..release();
    await tester.pump();
    expect(players.playerCount, 3);
    expect(c.player, same(outputs.created[2].player));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(evicted, <String>['a', 'b']);
    expect(players.playerCount, 0);
    // Held and free players alike are disposed, not kept.
    expect(outputs.created.map((FakeOutput o) => o.disposed), <bool>[
      true,
      true,
      true,
    ]);
    expect(outputs.created[0].calls, isNot(contains('stop')));

    expect(players.canAcquire(2), isFalse);
    expect(take(players, 'd', 2), isNull);
    expect(outputs.created, hasLength(3));

    notified = 0;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(notified, 1);
    expect(take(players, 'd', 1), isNotNull);
    expect(outputs.created, hasLength(4));
    expect(evicted, <String>['a', 'b']);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });

  testWidgets('pauses while inactive when asked, and plays on resuming', (
    tester,
  ) async {
    final VideoPlayers players = _players(outputs)..pausesWhileInactive = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final VideoLease a = take(players, 'a', 1)!;
    final VideoLease b = take(players, 'b', 1)!;
    await a.open(Media('/videos/a.webm'), setUp: _noSetUp);
    await b.open(Media('/videos/b.webm'), setUp: _noSetUp);
    await a.player.play();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(a.player.state.playing, isFalse);
    expect(outputs.created[1].calls, isNot(contains('pause')));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(a.player.state.playing, isTrue);
    // b was paused already, and stays so.
    expect(b.player.state.playing, isFalse);
    expect(outputs.created[1].calls, isNot(contains('play')));
  });

  group("a reused player's first frame", () {
    // A lease on a player that played another video before.
    Future<(VideoLease, FakeOutput)> reused(
      WidgetTester tester,
      VideoPlayers players,
    ) async {
      final VideoLease first = take(players, 'first', 1)!;
      await first.open(Media('/videos/first.webm'), setUp: _noSetUp);
      final FakeOutput output = outputs.created.single;
      output.showFirstFrame();
      await tester.pump();
      first.release();
      await tester.pump();
      final VideoLease lease = take(players, 'second', 1)!;
      expect(lease.player, same(output.player));
      return (lease, output);
    }

    testWidgets('comes once mpv decoded it and then restarted playback', (
      tester,
    ) async {
      final VideoPlayers players = _players(outputs);
      final (VideoLease lease, FakeOutput output) = await reused(
        tester,
        players,
      );
      bool shown = false;
      lease.firstFrame.then((_) => shown = true);

      // What mpv says before this lease opens its video is about the last
      // one.
      output.player.decode();
      output.restart();
      await tester.pump();
      expect(shown, isFalse);

      await lease.open(Media('/videos/second.webm'), setUp: _noSetUp);
      await tester.pump();
      expect(shown, isFalse);

      // No picture yet.
      output.player.emitVideoParams(const VideoParams(dw: 0, dh: 0));
      await tester.pump();
      expect(shown, isFalse);

      output.player.decode();
      await tester.pump();
      expect(shown, isFalse);
      output.restart();
      await tester.pump();
      expect(shown, isTrue);
    });

    testWidgets('comes once mpv restarted playback and then decoded it', (
      tester,
    ) async {
      final VideoPlayers players = _players(outputs);
      final (VideoLease lease, FakeOutput output) = await reused(
        tester,
        players,
      );
      bool shown = false;
      lease.firstFrame.then((_) => shown = true);
      await lease.open(Media('/videos/second.webm'), setUp: _noSetUp);

      output.restart();
      await tester.pump();
      expect(shown, isFalse);
      output.player.decode();
      await tester.pump();
      expect(shown, isTrue);
    });

    testWidgets('waits for a surface its size, and the restart after', (
      tester,
    ) async {
      final VideoPlayers players = _players(outputs);
      final (VideoLease lease, FakeOutput output) = await reused(
        tester,
        players,
      );
      bool shown = false;
      lease.firstFrame.then((_) => shown = true);
      await lease.open(Media('/videos/second.webm'), setUp: _noSetUp);

      // On Android, still on the last video's surface: squashed.
      output.drawsAtVideoSize = false;
      output.player.decode();
      output.restart();
      await tester.pump();
      expect(shown, isFalse);

      // Switched; mpv says the video's parameters again, then draws it
      // there.
      output.drawsAtVideoSize = true;
      output.player.decode();
      await tester.pump();
      expect(shown, isFalse);
      output.restart();
      await tester.pump();
      expect(shown, isTrue);
    });

    testWidgets("not the output's own first frame", (tester) async {
      final VideoPlayers players = _players(outputs);
      final (VideoLease lease, FakeOutput output) = await reused(
        tester,
        players,
      );
      bool shown = false;
      lease.firstFrame.then((_) => shown = true);
      await lease.open(Media('/videos/second.webm'), setUp: _noSetUp);
      // Reported long ago, for its first video.
      output.reportFirstFrame();
      await tester.pump();
      expect(shown, isFalse);
    });
  });

  testWidgets("a new player's first frame is its output's, unless sized up "
      'front', (tester) async {
    final VideoPlayers players = _players(outputs, sizesUpFront: true);
    final VideoLease sized = take(
      players,
      'sized',
      1,
      width: 640,
      height: 360,
    )!;
    final VideoLease unsized = take(players, 'unsized', 1)!;
    expect(outputs.created[0].size, (640, 360));
    expect(outputs.created[1].size, (null, null));
    await sized.open(Media('/videos/sized.webm'), setUp: _noSetUp);
    await unsized.open(Media('/videos/unsized.webm'), setUp: _noSetUp);
    // Made at their size: not resized as they open.
    expect(outputs.created[0].sizes, isEmpty);
    expect(outputs.created[1].sizes, isEmpty);

    bool sizedShown = false;
    bool unsizedShown = false;
    sized.firstFrame.then((_) => sizedShown = true);
    unsized.firstFrame.then((_) => unsizedShown = true);
    outputs.created[1].reportFirstFrame();
    // media_kit's sized output reports one before mpv has drawn anything.
    outputs.created[0].reportFirstFrame();
    await tester.pump();
    expect(unsizedShown, isTrue);
    expect(sizedShown, isFalse);

    outputs.created[0].player.decode();
    outputs.created[0].restart();
    await tester.pump();
    expect(sizedShown, isTrue);
  });

  group('sizing a reused player', () {
    testWidgets("sized up front, it takes the next video's size as that "
        'opens, after a frame', (tester) async {
      final VideoPlayers players = _players(outputs, sizesUpFront: true);
      final VideoLease a = take(players, 'a', 1, width: 640, height: 480)!;
      await a.open(Media('/videos/a.webm'), setUp: _noSetUp);
      a.release();
      await tester.pump();
      final FakeOutput output = outputs.created.single;

      final VideoLease b = take(players, 'b', 1, width: 320, height: 240)!;
      // Not yet: a's video may still be on screen.
      expect(output.sizes, isEmpty);
      final Future<bool> opening = b.open(
        Media('/videos/b.webm'),
        setUp: _noSetUp,
      );
      await tester.idle();
      expect(output.sizes, isEmpty);
      expect(output.player.opened, hasLength(1));

      await tester.pump();
      expect(output.sizes, <(int?, int?)>[(320, 240)]);
      expect(await opening, isTrue);
      expect(
        output.calls,
        containsAllInOrder(<String>['setSize 320x240', 'open /videos/b.webm']),
      );

      // A video of unknown size gets the video's own.
      b.release();
      await tester.pump();
      final VideoLease c = take(players, 'c', 1)!;
      final Future<bool> openingC = c.open(
        Media('/videos/c.webm'),
        setUp: _noSetUp,
      );
      await tester.pump();
      await tester.pump();
      expect(await openingC, isTrue);
      expect(output.sizes.last, (null, null));
    });

    testWidgets('not sized up front, it is never resized', (tester) async {
      final VideoPlayers players = _players(outputs);
      final VideoLease a = take(players, 'a', 1, width: 640, height: 480)!;
      expect(outputs.created.single.size, (null, null));
      await a.open(Media('/videos/a.webm'), setUp: _noSetUp);
      a.release();
      await tester.pump();

      final VideoLease b = take(players, 'b', 1, width: 320, height: 240)!;
      expect(await b.open(Media('/videos/b.webm'), setUp: _noSetUp), isTrue);
      await tester.pump();
      expect(outputs.created.single.sizes, isEmpty);
    });
  });
}
