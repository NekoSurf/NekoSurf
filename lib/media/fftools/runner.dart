// Adapted from media_kit's fftools (moffatman/media-kit, media_kit/lib/src/
// fftools/common.dart), under its MIT licence: see fftools.dart.

import 'package:async/async.dart';

enum FFTool { ffmpeg, ffprobe }

/// Runs one fftools command; [FFTools] uses the native one.
abstract interface class FFToolsRunner {
  /// Starts [tool] with [arguments] and completes with its return code.
  /// [onLog] hears each message with its FFmpeg log level (lower is more
  /// serious; what ffprobe prints is info, 32).
  CancelableOperation<int> run(
    FFTool tool,
    List<String> arguments, {
    required void Function(int level, String message) onLog,
    void Function(FFmpegStatistics statistics)? onStatistics,
  });
}

/// One of ffmpeg's progress reports.
class FFmpegStatistics {
  const FFmpegStatistics({
    required this.frameNumber,
    required this.fps,
    required this.quality,
    required this.size,
    required this.timeMs,
    required this.bitrate,
    required this.speed,
  });

  final int frameNumber;
  final double fps;
  final double quality;

  /// Bytes written so far.
  final int size;

  /// How far into the input it's got, in milliseconds.
  final int timeMs;

  /// Kilobits per second.
  final double bitrate;
  final double speed;
}
