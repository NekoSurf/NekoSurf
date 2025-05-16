import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/watched_media.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WatchedMediaProvider with ChangeNotifier, WidgetsBindingObserver {
  WatchedMediaProvider() {
    loadWatchedMedia();

    WidgetsBinding.instance.addObserver(this);

    _startCleanupTimer();
  }

  Timer? _cleanupTimer;

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      clearOldWatchedMedia();
    });
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      clearOldWatchedMedia();
    }
  }

  final List<WatchedMedia> _watchedMedia = [];
  List<WatchedMedia> get watchedMedia => List.unmodifiable(_watchedMedia);

  Future<void> loadWatchedMedia() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String>? watchedMediaList = prefs.getStringList('watchedMedia');

    if (watchedMediaList != null) {
      _watchedMedia.clear();
      for (final String mediaString in watchedMediaList) {
        try {
          final Map<String, dynamic> mediaMap =
              json.decode(mediaString) as Map<String, dynamic>;
          _watchedMedia.add(WatchedMedia.fromJson(mediaMap));
        } catch (e) {
          debugPrint('Error parsing watched media entry: $e');
        }
      }
      notifyListeners();
    }

    clearOldWatchedMedia();
  }

  Future<void> markAsWatched({
    required int mediaId,
    required int thread,
    required String fileName,
    required String ext,
  }) async {
    final WatchedMedia newWatchedMedia = WatchedMedia(
      mediaId: mediaId,
      thread: thread,
      fileName: fileName,
      ext: ext,
      watchedAt: DateTime.now(),
    );

    final existingMediaIndex = _watchedMedia.indexWhere(
        (media) => media.mediaId == mediaId && media.thread == thread);

    if (existingMediaIndex != -1) {
      _watchedMedia[existingMediaIndex] = newWatchedMedia;
    } else {
      _watchedMedia.add(newWatchedMedia);
    }

    await _saveWatchedMedia();
    notifyListeners();
  }

  Future<void> removeFromWatched(int mediaId, int thread) async {
    _watchedMedia.removeWhere(
        (media) => media.mediaId == mediaId && media.thread == thread);
    await _saveWatchedMedia();
    notifyListeners();
  }

  bool isWatched(int mediaId, int thread) {
    return _watchedMedia
        .any((media) => media.mediaId == mediaId && media.thread == thread);
  }

  Future<void> _saveWatchedMedia() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> watchedMediaStrings =
        _watchedMedia.map((media) => json.encode(media.toJson())).toList();
    await prefs.setStringList('watchedMedia', watchedMediaStrings);
  }

  Future<void> clearAllWatchedMedia() async {
    _watchedMedia.clear();
    await _saveWatchedMedia();
    notifyListeners();
  }

  Future<void> clearOldWatchedMedia() async {
    final settings = await SharedPreferences.getInstance();
    final int retentionDays = settings.getInt('watchedMediaRetentionDays') ?? 7;

    final DateTime cutoffDate =
        DateTime.now().subtract(Duration(days: retentionDays));

    _watchedMedia.removeWhere((media) => media.watchedAt.isBefore(cutoffDate));

    await _saveWatchedMedia();
    notifyListeners();
  }

  WatchedMedia? getLatestWatchedMedia(int thread) {
    final threadMedia =
        _watchedMedia.where((media) => media.thread == thread).toList();

    if (threadMedia.isEmpty) {
      return null;
    }

    return threadMedia
        .reduce((a, b) => a.watchedAt.isAfter(b.watchedAt) ? a : b);
  }
}
