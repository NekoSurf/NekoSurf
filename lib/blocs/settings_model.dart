import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_chan/services/string.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  SettingsProvider() {
    loadPreferences();
  }

  bool allowNSFW = false;
  Sort boardSort = Sort.byImagesCount;
  SortDirection boardSortDirection = SortDirection.desc;
  ViewMode boardViewMode = ViewMode.grid;
  int watchedPostsRetentionDays = 7;
  bool autoScrollToLastSeen = false;
  bool showStickyThreads = true;
  bool feedVideosStartMuted = true;
  bool trackHistory = true;
  List<String> hiddenThreadPatterns = [];
  List<RegExp>? _hiddenPatternRegexes;

  Future<void> loadPreferences() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    if (prefs.getString('boardSort') != null) {
      final Sort boardSortPrefs = Sort.values.firstWhere(
        (element) => element.name == prefs.getString('boardSort'),
      );
      boardSort = boardSortPrefs;
    }

    if (prefs.getString('boardSortDirection') != null) {
      boardSortDirection = SortDirection.values.firstWhere(
        (element) => element.name == prefs.getString('boardSortDirection'),
      );
    }

    if (prefs.getBool('allowNSFW') != null) {
      final bool? allowNSFWPrefs = prefs.getBool('allowNSFW');

      allowNSFW = allowNSFWPrefs!;
    }

    await prefs.remove('useCachingOnVideos');

    if (prefs.getInt('watchedPostsRetentionDays') != null) {
      watchedPostsRetentionDays = prefs.getInt('watchedPostsRetentionDays')!;
    }

    if (prefs.getBool('autoScrollToLastSeen') != null) {
      autoScrollToLastSeen = prefs.getBool('autoScrollToLastSeen')!;
    }

    if (prefs.getString('boardViewMode') != null) {
      boardViewMode = ViewMode.values.firstWhere(
        (element) => element.name == prefs.getString('boardViewMode'),
        orElse: () => ViewMode.grid,
      );
    }

    if (prefs.getBool('showStickyThreads') != null) {
      showStickyThreads = prefs.getBool('showStickyThreads')!;
    }

    if (prefs.getBool('feedVideosStartMuted') != null) {
      feedVideosStartMuted = prefs.getBool('feedVideosStartMuted')!;
    }

    if (prefs.getBool('trackHistory') != null) {
      trackHistory = prefs.getBool('trackHistory')!;
    }

    hiddenThreadPatterns = prefs.getStringList('hiddenThreadPatterns') ?? [];

    await prefs.remove('inlineMediaInThreadFeed');

    notifyListeners();
  }

  bool getNSFW() {
    return allowNSFW;
  }

  Future<void> setNSFW(bool boolean) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    allowNSFW = boolean;
    prefs.setBool('allowNSFW', boolean);

    notifyListeners();
  }

  Sort getBoardSort() {
    return boardSort;
  }

  Future<void> setBoardSort(Sort sort) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    boardSort = sort;
    prefs.setString('boardSort', sort.name);

    notifyListeners();
  }

  SortDirection getBoardSortDirection() {
    return boardSortDirection;
  }

  Future<void> setBoardSortDirection(SortDirection direction) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    boardSortDirection = direction;
    prefs.setString('boardSortDirection', direction.name);

    notifyListeners();
  }

  bool getAutoScrollToLastSeen() {
    return autoScrollToLastSeen;
  }

  Future<void> setAutoScrollToLastSeen(bool value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    autoScrollToLastSeen = value;
    prefs.setBool('autoScrollToLastSeen', value);

    notifyListeners();
  }

  int getWatchedPostsRetentionDays() {
    return watchedPostsRetentionDays;
  }

  Future<void> setWatchedPostsRetentionDays(int days) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    watchedPostsRetentionDays = days;
    prefs.setInt('watchedPostsRetentionDays', days);
    notifyListeners();
  }

  ViewMode getBoardViewMode() {
    return boardViewMode;
  }

  Future<void> setBoardViewMode(ViewMode mode) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    boardViewMode = mode;
    prefs.setString('boardViewMode', mode.name);
    notifyListeners();
  }

  bool getShowStickyThreads() {
    return showStickyThreads;
  }

  Future<void> setShowStickyThreads(bool value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    showStickyThreads = value;
    prefs.setBool('showStickyThreads', value);
    notifyListeners();
  }

  bool getFeedVideosStartMuted() {
    return feedVideosStartMuted;
  }

  Future<void> setFeedVideosStartMuted(bool value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    feedVideosStartMuted = value;
    prefs.setBool('feedVideosStartMuted', value);
    notifyListeners();
  }

  bool getTrackHistory() {
    return trackHistory;
  }

  Future<void> setTrackHistory(bool value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    trackHistory = value;
    prefs.setBool('trackHistory', value);
    notifyListeners();
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

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    hiddenThreadPatterns = [...hiddenThreadPatterns, trimmed];
    _hiddenPatternRegexes = null;
    prefs.setStringList('hiddenThreadPatterns', hiddenThreadPatterns);
    notifyListeners();
  }

  Future<void> removeHiddenThreadPattern(String pattern) async {
    if (!hiddenThreadPatterns.contains(pattern)) {
      return;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    hiddenThreadPatterns = hiddenThreadPatterns
        .where((p) => p != pattern)
        .toList();
    _hiddenPatternRegexes = null;
    prefs.setStringList('hiddenThreadPatterns', hiddenThreadPatterns);
    notifyListeners();
  }
}
