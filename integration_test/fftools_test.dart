// Runs saving's ffmpeg work for real, with the FFmpeg in media_kit's
// libraries, on a simulator or phone:
//
//   flutter test integration_test/fftools_test.dart -d <simulator id>
//
// Use a simulator: on a phone this replaces the installed app and its data.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_chan/media/fftools/fftools.dart';
import 'package:flutter_chan/saved/downloads.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

late Directory _dir;

const int _width = 853;
const int _height = 480;
const int _fps = 15;
const int _sampleRate = 44100;

/// Moving stripes, as raw frames ffmpeg reads (the build has no lavfi to
/// make test pictures with).
Future<File> _y4m(String name, int frames) async {
  final BytesBuilder bytes = BytesBuilder(copy: false)
    ..add(ascii.encode('YUV4MPEG2 W$_width H$_height F$_fps:1 Ip A1:1 C420\n'));
  const int chroma = ((_width + 1) ~/ 2) * ((_height + 1) ~/ 2);
  final Uint8List grey = Uint8List(chroma * 2)..fillRange(0, chroma * 2, 128);
  for (int frame = 0; frame < frames; frame++) {
    final Uint8List row = Uint8List.fromList([
      for (int x = 0; x < _width; x++) (x + frame * 8) & 0xff,
    ]);
    bytes.add(ascii.encode('FRAME\n'));
    for (int y = 0; y < _height; y++) {
      bytes.add(row);
    }
    bytes.add(grey);
  }
  return File('${_dir.path}/$name.y4m').writeAsBytes(bytes.takeBytes());
}

/// A 440 Hz tone, as raw 16-bit mono samples.
Future<File> _pcm(String name, double seconds) {
  final ByteData data = ByteData((seconds * _sampleRate).round() * 2);
  for (int i = 0; i < data.lengthInBytes ~/ 2; i++) {
    final double t = i / _sampleRate;
    data.setInt16(i * 2, (8000 * sin(2 * pi * 440 * t)).round(), Endian.little);
  }
  return File('${_dir.path}/$name.pcm').writeAsBytes(data.buffer.asUint8List());
}

/// A VP9 webm with Vorbis sound, of an odd size as 4chan's often are.
Future<File> _webm(String name, {double seconds = 2}) async {
  final File video = await _y4m(name, (seconds * _fps).ceil());
  final File audio = await _pcm(name, seconds);
  final File file = File('${_dir.path}/$name.webm');
  final FFToolsOutput result = await FFTools.ffmpeg([
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-f',
    'yuv4mpegpipe',
    '-i',
    video.path,
    '-f',
    's16le',
    '-ar',
    '$_sampleRate',
    '-ac',
    '1',
    '-i',
    audio.path,
    '-c:v',
    'libvpx-vp9',
    '-deadline',
    'realtime',
    '-cpu-used',
    '8',
    '-b:v',
    '500k',
    '-c:a',
    'libvorbis',
    '-shortest',
    file.path,
  ]).value;
  expect(result.returnCode, 0, reason: result.output);
  return file;
}

Future<List<Map<String, dynamic>>> _streams(File file) async {
  final FFToolsOutput result = await FFTools.ffprobe([
    '-hide_banner',
    '-loglevel',
    'error',
    '-print_format',
    'json',
    '-show_streams',
    file.path,
  ]);
  expect(result.returnCode, 0, reason: result.output);
  return (jsonDecode(result.output)['streams'] as List)
      .cast<Map<String, dynamic>>();
}

/// Webms are converted only on iPhone, with Apple's encoder.
final bool _onlyIPhoneConverts = !Platform.isIOS;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  setUpAll(() async {
    _dir = await Directory.systemTemp.createTemp('fftools_test');
  });
  tearDownAll(() => _dir.delete(recursive: true));

  test('runs ffmpeg', () async {
    final FFToolsOutput result = await FFTools.ffmpeg(['-version']).value;
    expect(result.returnCode, 0);
    // ignore: avoid_print
    print(result.output.split('\n').first);
  });

  test('converts a webm to an mp4 Photos takes, with progress', () async {
    final File webm = await _webm("it's a \"clip\"");
    final File mp4 = File('${_dir.path}/clip.mp4');
    final List<double?> progress = <double?>[];

    await convertWebMToMP4(webm, mp4, progress.add);

    expect(progress.first, 0);
    expect(progress.last, 1);
    expect(progress.where((p) => p != null && p > 0 && p < 1), isNotEmpty);
    final List<Map<String, dynamic>> streams = await _streams(mp4);
    final Map<String, dynamic> video = streams.firstWhere(
      (s) => s['codec_type'] == 'video',
    );
    expect(video['codec_name'], 'h264');
    expect(video['pix_fmt'], 'yuv420p');
    expect((video['width'], video['height']), (852, 480));
    expect(
      streams.firstWhere((s) => s['codec_type'] == 'audio')['codec_name'],
      'aac',
    );
  }, skip: _onlyIPhoneConverts);

  test('converts two at once', () async {
    final List<File> webms = await Future.wait([_webm('a'), _webm('b')]);
    await Future.wait([
      for (final File webm in webms)
        convertWebMToMP4(
          webm,
          File(webm.path.replaceFirst('.webm', '.mp4')),
          (_) {},
        ),
    ]);
    for (final File webm in webms) {
      final File mp4 = File(webm.path.replaceFirst('.webm', '.mp4'));
      expect((await _streams(mp4)).first['codec_name'], 'h264');
    }
  }, skip: _onlyIPhoneConverts);

  test('grabs a thumbnail, even from a very short clip', () async {
    for (final double seconds in [2, 0.2]) {
      final File webm = await _webm('thumb$seconds', seconds: seconds);
      final File jpg = File('${_dir.path}/thumb$seconds.jpg');

      expect(await grabVideoFrame(webm.path, jpg), isTrue);

      final Map<String, dynamic> image = (await _streams(jpg)).single;
      expect(image['codec_name'], 'mjpeg');
      expect(image['width'], 480);
    }
  });

  // fftools leaves its log handler in the FFmpeg mpv plays with. Android
  // only: under the test on an iOS simulator mpv opens no audio device, and
  // without a VideoController (drawn in the app) it shows no video, so it
  // plays nothing there even before ffmpeg runs; check playback in the app.
  test('mpv still plays after ffmpeg has run', () async {
    final File webm = await _webm('play');
    expect(
      await grabVideoFrame(webm.path, File('${_dir.path}/play.jpg')),
      isTrue,
    );
    final Player player = Player();
    try {
      await player.open(Media(webm.uri.toString()));
      await player.stream.position
          .firstWhere((Duration p) => p > const Duration(milliseconds: 500))
          .timeout(const Duration(seconds: 10));
      expect(player.state.duration, greaterThan(const Duration(seconds: 1)));
      expect(
        player.state.tracks.video.map((VideoTrack t) => t.codec),
        contains('vp9'),
      );
    } finally {
      await player.dispose();
    }
  }, skip: Platform.isIOS);
}
