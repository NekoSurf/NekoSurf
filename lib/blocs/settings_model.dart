import 'package:flutter/material.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  SettingsProvider() {
    loadPreferences();
  }

  bool allowNSFW = false;
  Sort boardSort = Sort.byImagesCount;
  SortDirection boardSortDirection = SortDirection.desc;
  ViewMode boardViewMode = ViewMode.grid;
  int watchedMediaRetentionDays = 7;
  bool autoScrollToLastSeen = false;

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

    if (prefs.getInt('watchedMediaRetentionDays') != null) {
      watchedMediaRetentionDays = prefs.getInt('watchedMediaRetentionDays')!;
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

  int getWatchedMediaRetentionDays() {
    return watchedMediaRetentionDays;
  }

  Future<void> setWatchedMediaRetentionDays(int days) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    watchedMediaRetentionDays = days;
    prefs.setInt('watchedMediaRetentionDays', days);
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
}
