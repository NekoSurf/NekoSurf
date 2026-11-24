import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_chan/media/fftools/fftools.dart';

/// A video's size as it's shown: turned for a phone video filmed sideways,
/// and stretched for one whose pixels aren't square.
typedef VideoSize = ({int width, int height});

/// The size of the video file at [path], from ffprobe; null if it can't
/// tell.
Future<VideoSize?> probeVideoSize(String path) async {
  try {
    final FFToolsOutput result = await FFTools.ffprobe([
      // As every command sets it: FFmpeg's log level is shared with mpv.
      '-hide_banner',
      '-loglevel',
      'error',
      '-select_streams',
      'v:0',
      '-show_streams',
      '-print_format',
      'json',
      path,
    ]);
    if (result.succeeded) {
      return parseVideoSize(result.output);
    }
    debugPrint('Size probe failed for $path: ${result.output.trim()}');
  } catch (e) {
    debugPrint('Size probe failed for $path: $e');
  }
  return null;
}

/// The shown size of the first video stream in ffprobe's `-show_streams`
/// JSON, or null if it doesn't say.
@visibleForTesting
VideoSize? parseVideoSize(String json) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    return null;
  }
  final Object? streams = decoded is Map ? decoded['streams'] : null;
  final Object? stream = streams is List && streams.isNotEmpty
      ? streams.first
      : null;
  if (stream is! Map) {
    return null;
  }
  final int? codedWidth = int.tryParse('${stream['width']}');
  final int? height = int.tryParse('${stream['height']}');
  if (codedWidth == null || height == null || codedWidth <= 0 || height <= 0) {
    return null;
  }

  int width = codedWidth;
  final List<String> aspect = '${stream['sample_aspect_ratio']}'.split(':');
  if (aspect.length == 2) {
    final int? across = int.tryParse(aspect[0]);
    final int? down = int.tryParse(aspect[1]);
    if (across != null && down != null && across > 0 && down > 0) {
      width = (codedWidth * across / down).round();
    }
  }

  // Older files say it in a tag, newer ones in the display matrix.
  int rotation = 0;
  final Object? tags = stream['tags'];
  if (tags is Map) {
    rotation = int.tryParse('${tags['rotate']}') ?? 0;
  }
  final Object? sideData = stream['side_data_list'];
  if (sideData is List) {
    for (final Object? entry in sideData) {
      if (entry is Map && entry['rotation'] != null) {
        rotation = num.tryParse('${entry['rotation']}')?.round() ?? rotation;
      }
    }
  }
  return rotation.abs() % 180 == 90
      ? (width: height, height: width)
      : (width: width, height: height);
}
