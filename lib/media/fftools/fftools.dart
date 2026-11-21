// Adapted from media_kit's fftools (moffatman/media-kit, media_kit/lib/src/
// fftools), under its MIT licence:
//
// Copyright (c) 2021 & onwards Hitesh Kumar Saini <saini123hitesh@gmail.com>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.

import 'package:async/async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chan/media/fftools/native.dart';
import 'package:flutter_chan/media/fftools/runner.dart';

export 'package:flutter_chan/media/fftools/runner.dart'
    show FFmpegStatistics, FFTool, FFToolsRunner;

/// Runs `ffmpeg` and `ffprobe` with mpv's own FFmpeg: the encoder builds of
/// media_kit's libraries carry fftools, which runs the command-line tools
/// in-process, each command on a thread of its own.
///
/// Arguments are a list, as a shell would split them, so a path with spaces
/// or quotes in it is one argument as it is.
class FFTools {
  FFTools._();

  static FFToolsRunner? _runner;

  /// What runs the commands; tests set a fake. The real one loads fftools
  /// the first time it's needed.
  @visibleForTesting
  static set runner(FFToolsRunner? runner) => _runner = runner;

  static FFToolsRunner get _current => _runner ??= NativeFFTools.open();

  /// Runs `ffmpeg` with [arguments]. [onStatistics] hears how far it's got
  /// as it goes; cancelling the operation stops it.
  static CancelableOperation<FFToolsOutput> ffmpeg(
    List<String> arguments, {
    void Function(FFmpegStatistics statistics)? onStatistics,
  }) => _collect(FFTool.ffmpeg, arguments, onStatistics: onStatistics);

  /// Runs `ffprobe` with [arguments]; what it prints is in the output.
  static Future<FFToolsOutput> ffprobe(List<String> arguments) =>
      _collect(FFTool.ffprobe, arguments).value;

  static CancelableOperation<FFToolsOutput> _collect(
    FFTool tool,
    List<String> arguments, {
    void Function(FFmpegStatistics statistics)? onStatistics,
  }) {
    final StringBuffer output = StringBuffer();
    return _current
        .run(
          tool,
          arguments,
          onLog: (int level, String message) {
            if (level <= _logInfo) {
              output.write(message);
            }
          },
          onStatistics: onStatistics,
        )
        .then(
          (int returnCode) =>
              FFToolsOutput(returnCode: returnCode, output: output.toString()),
        );
  }

  /// FFmpeg's AV_LOG_INFO: what the tools print, and their warnings and
  /// errors, without their debugging chatter.
  static const int _logInfo = 32;
}

/// How a command ended, and what it printed.
class FFToolsOutput {
  const FFToolsOutput({required this.returnCode, required this.output});

  /// 0 if it worked.
  final int returnCode;
  final String output;

  bool get succeeded => returnCode == 0;
}
