import 'dart:convert';

import 'package:flutter_chan/media/video_size.dart';
import 'package:flutter_test/flutter_test.dart';

/// ffprobe's `-show_streams -print_format json` output for one stream.
String _probe(Map<String, Object?> stream) => jsonEncode(<String, Object?>{
  'streams': <Object?>[stream],
});

void main() {
  group('parseVideoSize', () {
    test('reads the size of a plain video', () {
      expect(
        parseVideoSize(
          _probe(<String, Object?>{
            'index': 0,
            'codec_type': 'video',
            'width': 640,
            'height': 360,
          }),
        ),
        (width: 640, height: 360),
      );
    });

    test('takes the first stream', () {
      expect(
        parseVideoSize(
          jsonEncode(<String, Object?>{
            'streams': <Object?>[
              <String, Object?>{'width': 1280, 'height': 720},
              <String, Object?>{'width': 320, 'height': 240},
            ],
          }),
        ),
        (width: 1280, height: 720),
      );
    });

    test('turns a video filmed sideways, from its rotate tag', () {
      expect(
        parseVideoSize(
          _probe(<String, Object?>{
            'width': 1920,
            'height': 1080,
            'tags': <String, Object?>{'rotate': '90'},
          }),
        ),
        (width: 1080, height: 1920),
      );
    });

    test('turns a video filmed sideways, from its display matrix', () {
      expect(
        parseVideoSize(
          _probe(<String, Object?>{
            'width': 1920,
            'height': 1080,
            'side_data_list': <Object?>[
              <String, Object?>{
                'side_data_type': 'Display Matrix',
                'displaymatrix':
                    '\n00000000:            0       65536           0\n',
                'rotation': -90,
              },
            ],
          }),
        ),
        (width: 1080, height: 1920),
      );
    });

    test('the display matrix says it over the tag', () {
      expect(
        parseVideoSize(
          _probe(<String, Object?>{
            'width': 1920,
            'height': 1080,
            'tags': <String, Object?>{'rotate': '90'},
            'side_data_list': <Object?>[
              <String, Object?>{'side_data_type': 'Stereo 3D'},
              <String, Object?>{
                'side_data_type': 'Display Matrix',
                'rotation': 180,
              },
            ],
          }),
        ),
        (width: 1920, height: 1080),
      );
    });

    test('keeps upside-down and three-quarter turns right', () {
      expect(
        parseVideoSize(
          _probe(<String, Object?>{
            'width': 1920,
            'height': 1080,
            'tags': <String, Object?>{'rotate': '180'},
          }),
        ),
        (width: 1920, height: 1080),
      );
      expect(
        parseVideoSize(
          _probe(<String, Object?>{
            'width': 1920,
            'height': 1080,
            'side_data_list': <Object?>[
              <String, Object?>{'rotation': 270},
            ],
          }),
        ),
        (width: 1080, height: 1920),
      );
    });

    test('stretches a video whose pixels are not square', () {
      expect(
        parseVideoSize(
          _probe(<String, Object?>{
            'width': 720,
            'height': 480,
            'sample_aspect_ratio': '32:27',
          }),
        ),
        (width: 853, height: 480),
      );
      // Square, or not said: as coded.
      expect(
        parseVideoSize(
          _probe(<String, Object?>{
            'width': 720,
            'height': 480,
            'sample_aspect_ratio': '1:1',
          }),
        ),
        (width: 720, height: 480),
      );
      expect(
        parseVideoSize(
          _probe(<String, Object?>{
            'width': 720,
            'height': 480,
            'sample_aspect_ratio': '0:1',
          }),
        ),
        (width: 720, height: 480),
      );
      expect(
        parseVideoSize(
          _probe(<String, Object?>{
            'width': 720,
            'height': 480,
            'sample_aspect_ratio': 'N/A',
          }),
        ),
        (width: 720, height: 480),
      );
    });

    test('stretches before turning', () {
      expect(
        parseVideoSize(
          _probe(<String, Object?>{
            'width': 720,
            'height': 480,
            'sample_aspect_ratio': '4:3',
            'tags': <String, Object?>{'rotate': '-90'},
          }),
        ),
        (width: 480, height: 960),
      );
    });

    test('reads sizes given as text', () {
      expect(
        parseVideoSize(
          _probe(<String, Object?>{'width': '640', 'height': '360'}),
        ),
        (width: 640, height: 360),
      );
    });

    test('is null when it cannot tell', () {
      for (final String output in <String>[
        '',
        'not json',
        'null',
        '[]',
        '{}',
        '{"streams": null}',
        '{"streams": []}',
        '{"streams": ["video"]}',
        _probe(<String, Object?>{'width': 640}),
        _probe(<String, Object?>{'height': 360}),
        _probe(<String, Object?>{'width': 0, 'height': 360}),
        _probe(<String, Object?>{'width': 640, 'height': -1}),
        _probe(<String, Object?>{'width': 'wide', 'height': 360}),
        _probe(<String, Object?>{'width': null, 'height': null}),
      ]) {
        expect(parseVideoSize(output), isNull, reason: output);
      }
    });
  });
}
