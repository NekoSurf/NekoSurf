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
  }

  Future<void> markAsWatched({
    required int mediaId,
    required String board,
    required String fileName,
    required String ext,
  }) async {
    final WatchedMedia newWatchedMedia = WatchedMedia(
      mediaId: mediaId,
      board: board,
      fileName: fileName,
      ext: ext,
      watchedAt: DateTime.now(),
    );

    if (!_watchedMedia.contains(newWatchedMedia)) {
      _watchedMedia.add(newWatchedMedia);
      await _saveWatchedMedia();
      notifyListeners();
    }
  }

  Future<void> removeFromWatched(int mediaId, String board) async {
    _watchedMedia.removeWhere(
        (media) => media.mediaId == mediaId && media.board == board);
    await _saveWatchedMedia();
    notifyListeners();
  }

  bool isWatched(int mediaId, String board) {
    return _watchedMedia
        .any((media) => media.mediaId == mediaId && media.board == board);
  }

  Future<void> _saveWatchedMedia() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> watchedMediaStrings =
        _watchedMedia.map((media) => json.encode(media.toJson())).toList();
    await prefs.setStringList('watchedMedia', watchedMediaStrings);
  }
}
