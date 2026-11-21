import 'dart:io';

import 'package:async/async.dart';
import 'package:flutter_chan/media/fftools/fftools.dart';
import 'package:flutter_chan/saved/downloads.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers ffprobe with [probe] and runs ffmpeg by reporting [times] (in
/// milliseconds) and ending with [ffmpegCode].
class _FakeFFTools implements FFToolsRunner {
  _FakeFFTools({
    this.probe = '{"format": {"duration": "4.000000", "bit_rate": "1000"}}',
    this.times = const <int>[],
    this.ffmpegCode = 0,
  });

  final String probe;
  final List<int> times;
  final int ffmpegCode;
  final List<(FFTool, List<String>)> calls = [];

  @override
  CancelableOperation<int> run(
    FFTool tool,
    List<String> arguments, {
    required void Function(int level, String message) onLog,
    void Function(FFmpegStatistics statistics)? onStatistics,
  }) {
    calls.add((tool, arguments));
    if (tool == FFTool.ffprobe) {
      onLog(-16, probe);
      return CancelableOperation.fromValue(0);
    }
    for (final int time in times) {
      onStatistics?.call(
        FFmpegStatistics(
          frameNumber: 0,
          fps: 0,
          quality: 0,
          size: 0,
          timeMs: time,
          bitrate: 0,
          speed: 0,
        ),
      );
    }
    if (ffmpegCode != 0) {
      onLog(16, 'Conversion failed!\n');
    }
    return CancelableOperation.fromValue(ffmpegCode);
  }
}

void main() {
  tearDown(() => FFTools.runner = null);

  group('parseProbe', () {
    test('reads the bitrate and the length in milliseconds', () {
      expect(
        parseProbe(
          '{"format": {"filename": "a.webm", "duration": "2.503000", '
          '"size": "312345", "bit_rate": "998305"}}',
        ),
        (998305, 2503),
      );
    });

    test("is null for what it doesn't say", () {
      expect(parseProbe('{"format": {"filename": "a.webm"}}'), (null, null));
      expect(parseProbe('{"format": {"duration": "N/A"}}'), (null, null));
      expect(parseProbe('{"format": {"duration": "0.000000"}}'), (null, null));
    });

    test("is null for output that isn't ffprobe's", () {
      expect(parseProbe(''), (null, null));
      expect(parseProbe('[]'), (null, null));
      expect(parseProbe('{}'), (null, null));
    });
  });

  group('convertWebMToMP4', () {
    final File webm = File("/tmp/it's a \"clip\".webm");
    final File mp4 = File("/tmp/it's a \"clip\".mp4");

    test('converts at twice the bitrate, with paths as they are', () async {
      final _FakeFFTools fftools = _FakeFFTools();
      FFTools.runner = fftools;

      await convertWebMToMP4(webm, mp4, (_) {});

      expect(fftools.calls.map((call) => call.$1), [
        FFTool.ffprobe,
        FFTool.ffmpeg,
      ]);
      expect(fftools.calls.first.$2.last, webm.path);
      final List<String> ffmpeg = fftools.calls.last.$2;
      expect(ffmpeg[ffmpeg.indexOf('-i') + 1], webm.path);
      expect(ffmpeg[ffmpeg.indexOf('-b:v') + 1], '2000');
      expect(ffmpeg[ffmpeg.indexOf('-c:v') + 1], 'h264_videotoolbox');
      expect(ffmpeg.last, mp4.path);
    });

    test('reports how far it is through the video', () async {
      FFTools.runner = _FakeFFTools(times: [0, 1000, 3000, 5000]);
      final List<double?> progress = <double?>[];

      await convertWebMToMP4(webm, mp4, progress.add);

      expect(progress, [0, 0, 0.25, 0.75, 1, 1]);
    });

    test("spins when the webm doesn't say how long it is", () async {
      final _FakeFFTools fftools = _FakeFFTools(
        probe: '{"format": {}}',
        times: [1000],
      );
      FFTools.runner = fftools;
      final List<double?> progress = <double?>[];

      await convertWebMToMP4(webm, mp4, progress.add);

      expect(progress, [null, 1]);
      final List<String> ffmpeg = fftools.calls.last.$2;
      expect(ffmpeg[ffmpeg.indexOf('-b:v') + 1], '4000000');
    });

    test("throws with ffmpeg's error when it fails", () async {
      FFTools.runner = _FakeFFTools(ffmpegCode: 1);

      await expectLater(
        convertWebMToMP4(webm, mp4, (_) {}),
        throwsA(
          isA<Exception>().having(
            (Exception e) => '$e',
            'message',
            contains('Conversion failed!'),
          ),
        ),
      );
    });
  });
}
