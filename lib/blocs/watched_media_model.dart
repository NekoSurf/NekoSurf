import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/watched_media.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WatchedMediaProvider with ChangeNotifier {
  WatchedMediaProvider() {
    loadWatchedMedia();
  }

  final List<WatchedMedia> _watchedMedia = [];
  List<WatchedMedia> get watchedMedia => List.unmodifiable(_watchedMedia);

  Future<void> loadWatchedMedia() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String>? watchedMediaList = prefs.getStringList('watchedMedia');

    if (watchedMediaList != null) {
      _watchedMedia.clear();
      for (final String mediaString in watchedMediaList) {
        final Map<String, dynamic> mediaMap =
            json.decode(mediaString) as Map<String, dynamic>;
        _watchedMedia.add(WatchedMedia.fromJson(mediaMap));
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

    if (!_watchedMedia.contains(newWatchedMedia)) {
      _watchedMedia.add(newWatchedMedia);
      await _saveWatchedMedia();
      notifyListeners();
    }

    clearOldWatchedMedia();
  }

  Future<void> removeFromWatched(int mediaId, int thread) async {
    _watchedMedia.removeWhere(
        (media) => media.mediaId == mediaId && media.thread == thread);
    await _saveWatchedMedia();
    notifyListeners();

    clearOldWatchedMedia();
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
