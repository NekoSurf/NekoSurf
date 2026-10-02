import 'package:flutter/material.dart';

class ThemeChanger with ChangeNotifier {
  ThemeChanger(this._themeData) {
    loadPreferences();
  }

  ThemeData _themeData;

  Future<void> loadPreferences() async {
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final bool isDarkMode = brightness == Brightness.dark;

    setTheme(isDarkMode ? ThemeData.dark() : ThemeData.light());

    notifyListeners();
  }

  ThemeData getTheme() => _themeData;

  void setTheme(ThemeData theme) {
    _themeData = theme;

    notifyListeners();
  }
}
