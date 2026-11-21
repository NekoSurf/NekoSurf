// Adapted from media_kit's fftools (moffatman/media-kit, media_kit/lib/src/
// fftools/vm.dart), under its MIT licence: see fftools.dart.

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:async/async.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_chan/media/fftools/runner.dart';

// The messages fftools posts to a command's port: each is the address of an
// FFToolsMessage it allocated, which the receiver frees.
const int _messageReturnCode = 0;
const int _messageLog = 1;
const int _messageStatistics = 2;

final class _Message extends Struct {
  @Int32()
  external int type;
  external _MessageData data;
}

final class _MessageData extends Union {
  @Int32()
  external int returnCode;
  external _Log log;
  external _Statistics statistics;
}

final class _Log extends Struct {
  @Int32()
  external int level;
  external Pointer<Utf8> message;
}

final class _Statistics extends Struct {
  @Int32()
  external int frameNumber;
  @Float()
  external double fps;
  @Float()
  external double quality;
  @Int64()
  external int size;
  @Int32()
  external int time;
  @Double()
  external double bitrate;
  @Double()
  external double speed;
}

typedef _ExecuteC = Void Function(Int64, Int, Pointer<Pointer<Utf8>>);
typedef _Execute = void Function(int, int, Pointer<Pointer<Utf8>>);

/// fftools in the app's own libraries: the Fftools-ffi framework on iOS,
/// and linked into libmpv.so on Android.
class NativeFFTools implements FFToolsRunner {
  NativeFFTools._(DynamicLibrary library)
    : _ffmpeg = library.lookupFunction<_ExecuteC, _Execute>(
        'FFToolsFFIExecuteFFmpeg',
      ),
      _ffprobe = library.lookupFunction<_ExecuteC, _Execute>(
        'FFToolsFFIExecuteFFprobe',
      ),
      _cancel = library
          .lookupFunction<Void Function(Int64), void Function(int)>(
            'FFToolsCancel',
          ) {
    library.lookupFunction<Void Function(Pointer), void Function(Pointer)>(
      'FFToolsFFIInitialize',
    )(NativeApi.postCObject);
  }

  /// Loads fftools; throws if this build of the app doesn't have it.
  factory NativeFFTools.open() {
    final String name = Platform.isIOS || Platform.isMacOS
        ? 'Fftools-ffi.framework/Fftools-ffi'
        : 'libmpv.so';
    return NativeFFTools._(DynamicLibrary.open(name));
  }

  final _Execute _ffmpeg;
  final _Execute _ffprobe;
  final void Function(int) _cancel;

  @override
  CancelableOperation<int> run(
    FFTool tool,
    List<String> arguments, {
    required void Function(int level, String message) onLog,
    void Function(FFmpegStatistics statistics)? onStatistics,
  }) {
    final ReceivePort port = ReceivePort();
    final CancelableCompleter<int> completer = CancelableCompleter<int>(
      // fftools still posts the return code, which closes the port.
      onCancel: () => _cancel(port.sendPort.nativePort),
    );
    // fftools frees these when the command is done.
    final Pointer<Pointer<Utf8>> argv = malloc<Pointer<Utf8>>(arguments.length);
    for (int i = 0; i < arguments.length; i++) {
      argv[i] = arguments[i].toNativeUtf8(allocator: malloc);
    }
    port.listen((dynamic address) {
      if (address is! int) {
        return;
      }
      final Pointer<_Message> message = Pointer<_Message>.fromAddress(address);
      switch (message.ref.type) {
        case _messageReturnCode:
          port.close();
          if (!completer.isCanceled) {
            completer.complete(message.ref.data.returnCode);
          }
        case _messageLog:
          final _Log log = message.ref.data.log;
          onLog(log.level, log.message.toDartString());
          malloc.free(log.message);
        case _messageStatistics:
          final _Statistics s = message.ref.data.statistics;
          onStatistics?.call(
            FFmpegStatistics(
              frameNumber: s.frameNumber,
              fps: s.fps,
              quality: s.quality,
              size: s.size,
              timeMs: s.time,
              bitrate: s.bitrate,
              speed: s.speed,
            ),
          );
      }
      malloc.free(message);
    });
    final _Execute execute = tool == FFTool.ffmpeg ? _ffmpeg : _ffprobe;
    execute(port.sendPort.nativePort, arguments.length, argv);
    return completer.operation;
  }
}
