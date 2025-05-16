import 'package:flutter/material.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  SettingsProvider() {
    loadPreferences();
  }

  bool allowNSFW = false;
  ViewType boardView = ViewType.gridView;
  Sort boardSort = Sort.byImagesCount;
  bool useCachingOnVideos = false;
  int watchedMediaRetentionDays = 7;

  Future<void> loadPreferences() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    if (prefs.getString('boardView') != null) {
      final ViewType boardViewPrefs = ViewType.values.firstWhere(
        (element) => element.name == prefs.getString('boardView'),
      );

      boardView = boardViewPrefs;
    }

    if (prefs.getString('boardSort') != null) {
      final Sort boardSortPrefs = Sort.values.firstWhere(
        (element) => element.name == prefs.getString('boardSort'),
      );
      boardSort = boardSortPrefs;
    }

    if (prefs.getBool('allowNSFW') != null) {
      final bool? allowNSFWPrefs = prefs.getBool('allowNSFW');

      allowNSFW = allowNSFWPrefs!;
    }

    if (prefs.getBool('useCachingOnVideos') != null) {
      final bool? useCachingOnVideosPrefs = prefs.getBool('useCachingOnVideos');

      useCachingOnVideos = useCachingOnVideosPrefs!;
    }

    if (prefs.getInt('watchedMediaRetentionDays') != null) {
      watchedMediaRetentionDays = prefs.getInt('watchedMediaRetentionDays')!;
    }

    notifyListeners();
  }

  bool getUseCachingOnVideos() {
    return useCachingOnVideos;
  }

  Future<void> setUseCachingOnVideos(bool boolean) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    useCachingOnVideos = boolean;
    prefs.setBool('useCachingOnVideos', boolean);

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

  ViewType getBoardView() {
    return boardView;
  }

  Future<void> setBoardView(ViewType view) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    boardView = view;
    prefs.setString('boardView', view.name);

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

  int getWatchedMediaRetentionDays() {
    return watchedMediaRetentionDays;
  }

  Future<void> setWatchedMediaRetentionDays(int days) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    watchedMediaRetentionDays = days;
    prefs.setInt('watchedMediaRetentionDays', days);
    notifyListeners();
  }
}
