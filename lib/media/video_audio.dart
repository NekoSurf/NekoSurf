import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Tells iPhone whether any video is heard, so videos play alongside other
/// apps' sound (music, a podcast) until one is, rather than stopping it as
/// each muted video in a thread loads (see VideoAudio in AppDelegate.swift).
class VideoAudio {
  VideoAudio._();

  static final VideoAudio instance = VideoAudio._();

  static const MethodChannel _channel = MethodChannel('nekosurf/video_audio');

  // A moment before letting other audio mix in again: closing fullscreen
  // hands the video to its post, which may be heard as well.
  static const Duration _letGoAfter = Duration(seconds: 1);

  final Set<Object> _heard = <Object>{};
  // What iOS was last told; videos mix with other audio from launch.
  bool _told = false;
  Timer? _letGo;

  /// Whether [video] plays with sound for someone now.
  void setHeard(Object video, bool heard) {
    if (!Platform.isIOS) {
      return;
    }
    if (!(heard ? _heard.add(video) : _heard.remove(video))) {
      return;
    }
    _letGo?.cancel();
    if (_heard.isNotEmpty) {
      _tell(true);
    } else {
      _letGo = Timer(_letGoAfter, () => _tell(false));
    }
  }

  void _tell(bool heard) {
    if (heard == _told) {
      return;
    }
    _told = heard;
    _channel
        .invokeMethod<void>('setHeard', heard)
        .catchError((Object error) => debugPrint('VideoAudio: $error'));
  }
}
