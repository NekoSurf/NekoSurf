import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_chan/services/string.dart';
import 'package:flutter_chan/services/video_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  SettingsProvider(this._prefs) {
    T? byName<T extends Enum>(List<T> values, String key) {
      final String? name = _prefs.getString(key);
      for (final T value in values) {
        if (value.name == name) {
          return value;
        }
      }
      return null;
    }

    boardSort = byName(Sort.values, 'boardSort') ?? boardSort;
    boardSortDirection =
        byName(SortDirection.values, 'boardSortDirection') ??
        boardSortDirection;
    boardViewMode = byName(ViewMode.values, 'boardViewMode') ?? boardViewMode;
    allowNSFW = _prefs.getBool('allowNSFW') ?? allowNSFW;
    watchedPostsRetentionDays =
        _prefs.getInt('watchedPostsRetentionDays') ?? watchedPostsRetentionDays;
    autoScrollToLastSeen =
        _prefs.getBool('autoScrollToLastSeen') ?? autoScrollToLastSeen;
    showStickyThreads =
        _prefs.getBool('showStickyThreads') ?? showStickyThreads;
    feedVideosStartMuted =
        _prefs.getBool('feedVideosStartMuted') ?? feedVideosStartMuted;
    trackHistory = _prefs.getBool('trackHistory') ?? trackHistory;
    fullscreenAutoAdvance =
        _prefs.getBool('fullscreenAutoAdvance') ?? fullscreenAutoAdvance;
    hiddenThreadPatterns = _prefs.getStringList('hiddenThreadPatterns') ?? [];
    videoCacheMegabytes =
        _prefs.getInt('videoCacheMegabytes') ?? videoCacheMegabytes;

    unawaited(
      VideoServer.instance.setMaxCacheBytes(videoCacheMegabytes * _megabyte),
    );
    // Settings that no longer exist.
    unawaited(_prefs.remove('useCachingOnVideos'));
    unawaited(_prefs.remove('inlineMediaInThreadFeed'));
  }

  final SharedPreferences _prefs;

  bool allowNSFW = false;
  Sort boardSort = Sort.byImagesCount;
  SortDirection boardSortDirection = SortDirection.desc;
  ViewMode boardViewMode = ViewMode.grid;
  int watchedPostsRetentionDays = 7;
  int videoCacheMegabytes = VideoServer.defaultMaxCacheBytes ~/ _megabyte;
  bool autoScrollToLastSeen = true;
  bool showStickyThreads = true;
  bool feedVideosStartMuted = true;
  bool trackHistory = true;
  bool fullscreenAutoAdvance = false;
  List<String> hiddenThreadPatterns = [];
  List<RegExp>? _hiddenPatternRegexes;

  static const int _megabyte = 1024 * 1024;

  /// Tells listeners right away and stores [value] under [key].
  Future<void> _save(String key, Object value) async {
    notifyListeners();
    if (value is bool) {
      await _prefs.setBool(key, value);
    } else if (value is int) {
      await _prefs.setInt(key, value);
    } else if (value is String) {
      await _prefs.setString(key, value);
    } else if (value is List<String>) {
      await _prefs.setStringList(key, value);
    }
  }

  bool getNSFW() => allowNSFW;

  Future<void> setNSFW(bool value) {
    allowNSFW = value;
    return _save('allowNSFW', value);
  }

  Sort getBoardSort() => boardSort;

  Future<void> setBoardSort(Sort sort) {
    boardSort = sort;
    return _save('boardSort', sort.name);
  }

  SortDirection getBoardSortDirection() => boardSortDirection;

  Future<void> setBoardSortDirection(SortDirection direction) {
    boardSortDirection = direction;
    return _save('boardSortDirection', direction.name);
  }

  bool getAutoScrollToLastSeen() => autoScrollToLastSeen;

  Future<void> setAutoScrollToLastSeen(bool value) {
    autoScrollToLastSeen = value;
    return _save('autoScrollToLastSeen', value);
  }

  int getWatchedPostsRetentionDays() => watchedPostsRetentionDays;

  Future<void> setWatchedPostsRetentionDays(int days) {
    watchedPostsRetentionDays = days;
    return _save('watchedPostsRetentionDays', days);
  }

  int getVideoCacheMegabytes() => videoCacheMegabytes;

  Future<void> setVideoCacheMegabytes(int megabytes) async {
    videoCacheMegabytes = megabytes;
    await _save('videoCacheMegabytes', megabytes);
    await VideoServer.instance.setMaxCacheBytes(megabytes * _megabyte);
  }

  ViewMode getBoardViewMode() => boardViewMode;

  Future<void> setBoardViewMode(ViewMode mode) {
    boardViewMode = mode;
    return _save('boardViewMode', mode.name);
  }

  bool getShowStickyThreads() => showStickyThreads;

  Future<void> setShowStickyThreads(bool value) {
    showStickyThreads = value;
    return _save('showStickyThreads', value);
  }

  bool getFeedVideosStartMuted() => feedVideosStartMuted;

  Future<void> setFeedVideosStartMuted(bool value) {
    feedVideosStartMuted = value;
    return _save('feedVideosStartMuted', value);
  }

  bool getTrackHistory() => trackHistory;

  Future<void> setTrackHistory(bool value) {
    trackHistory = value;
    return _save('trackHistory', value);
  }

  /// Fullscreen videos move on to the next item when they end, instead of
  /// looping.
  bool getFullscreenAutoAdvance() => fullscreenAutoAdvance;

  Future<void> setFullscreenAutoAdvance(bool value) {
    fullscreenAutoAdvance = value;
    return _save('fullscreenAutoAdvance', value);
  }

  List<String> getHiddenThreadPatterns() {
    return List.unmodifiable(hiddenThreadPatterns);
  }

  List<RegExp> get _threadFilters {
    _hiddenPatternRegexes ??= [
      for (final String pattern in hiddenThreadPatterns) _compile(pattern),
    ];
    return _hiddenPatternRegexes!;
  }

  static RegExp _compile(String pattern) {
    try {
      return RegExp(pattern, caseSensitive: false);
    } on FormatException {
      return RegExp(RegExp.escape(pattern), caseSensitive: false);
    }
  }

  bool isThreadHidden(Post post) {
    if (hiddenThreadPatterns.isEmpty) {
      return false;
    }

    final String text = unescape(
      cleanTags('${post.sub ?? ''}\n${post.com ?? ''}'),
    );

    for (final RegExp filter in _threadFilters) {
      if (filter.hasMatch(text)) {
        return true;
      }
    }
    return false;
  }

  Future<void> addHiddenThreadPattern(String pattern) async {
    final String trimmed = pattern.trim();
    if (trimmed.isEmpty || hiddenThreadPatterns.contains(trimmed)) {
      return;
    }

    hiddenThreadPatterns = [...hiddenThreadPatterns, trimmed];
    _hiddenPatternRegexes = null;
    await _save('hiddenThreadPatterns', hiddenThreadPatterns);
  }

  Future<void> removeHiddenThreadPattern(String pattern) async {
    if (!hiddenThreadPatterns.contains(pattern)) {
      return;
    }

    hiddenThreadPatterns = hiddenThreadPatterns
        .where((p) => p != pattern)
        .toList();
    _hiddenPatternRegexes = null;
    await _save('hiddenThreadPatterns', hiddenThreadPatterns);
  }
}
