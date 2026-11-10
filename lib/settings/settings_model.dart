import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_chan/chan/catalog.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/chan/post_text.dart';
import 'package:flutter_chan/thread/post_hiding.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bytes in the unit [SettingsProvider.videoCacheMegabytes] is in.
const int megabyte = 1024 * 1024;

enum ViewMode { grid, list }

/// Whether the app is light or dark.
enum Appearance {
  system,
  light,
  dark;

  /// How the app looks, given how the phone does.
  Brightness brightness(Brightness phone) => switch (this) {
    Appearance.system => phone,
    Appearance.light => Brightness.light,
    Appearance.dark => Brightness.dark,
  };
}

enum ThreadLayout { nested, flat }

class Setting<T> {
  Setting._(this._key, this._value, this._store, this._onChanged);

  final String _key;
  T _value;
  final Future<bool> Function(String key, T value) _store;
  final VoidCallback _onChanged;

  T get value => _value;

  Future<void> set(T value) async {
    _value = value;
    _onChanged();
    await _store(_key, value);
  }
}

/// A setting is one line here; loading and storing it follow from that.
class SettingsProvider with ChangeNotifier {
  SettingsProvider(this._prefs) {
    // Settings that no longer exist.
    unawaited(_prefs.remove('useCachingOnVideos'));
    unawaited(_prefs.remove('inlineMediaInThreadFeed'));
  }

  final SharedPreferences _prefs;

  late final Setting<bool> allowNSFW = _bool('allowNSFW', false);
  late final Setting<Appearance> appearance = _enum(
    'appearance',
    Appearance.values,
    Appearance.system,
  );
  late final Setting<ThemeColor> themeColor = _enum(
    'themeColor',
    ThemeColor.values,
    ThemeColor.cyan,
  );
  late final Setting<Sort> boardSort = _enum(
    'boardSort',
    Sort.values,
    Sort.byImagesCount,
  );
  late final Setting<SortDirection> boardSortDirection = _enum(
    'boardSortDirection',
    SortDirection.values,
    SortDirection.desc,
  );
  late final Setting<ViewMode> boardViewMode = _enum(
    'boardViewMode',
    ViewMode.values,
    ViewMode.grid,
  );
  late final Setting<ThreadLayout> threadLayout = _enum(
    'threadLayout',
    ThreadLayout.values,
    ThreadLayout.nested,
  );
  late final Setting<int> watchedPostsRetentionDays = _int(
    'watchedPostsRetentionDays',
    7,
  );
  late final Setting<int> videoCacheMegabytes = _int(
    'videoCacheMegabytes',
    300,
  );
  late final Setting<bool> autoScrollToLastSeen = _bool(
    'autoScrollToLastSeen',
    true,
  );
  late final Setting<bool> showStickyThreads = _bool('showStickyThreads', true);
  late final Setting<bool> feedVideosStartMuted = _bool(
    'feedVideosStartMuted',
    true,
  );
  late final Setting<bool> trackHistory = _bool('trackHistory', true);

  /// The Saved tab shows the latest saves first.
  late final Setting<bool> savedNewestFirst = _bool('savedNewestFirst', true);

  /// Fullscreen videos move on to the next item when they end, instead of
  /// looping.
  late final Setting<bool> fullscreenAutoAdvance = _bool(
    'fullscreenAutoAdvance',
    false,
  );

  /// Threads show thumbnails only: full images and videos load when opened.
  late final Setting<bool> dataSaver = _bool('dataSaver', false);

  /// Saved and shared files take 4chan's name for them, not the poster's.
  late final Setting<bool> serverFileNames = _bool('serverFileNames', false);

  Setting<bool> _bool(String key, bool byDefault) => Setting<bool>._(
    key,
    _prefs.getBool(key) ?? byDefault,
    _prefs.setBool,
    notifyListeners,
  );

  Setting<int> _int(String key, int byDefault) => Setting<int>._(
    key,
    _prefs.getInt(key) ?? byDefault,
    _prefs.setInt,
    notifyListeners,
  );

  Setting<T> _enum<T extends Enum>(String key, List<T> values, T byDefault) {
    final String? stored = _prefs.getString(key);
    return Setting<T>._(
      key,
      values.where((T value) => value.name == stored).firstOrNull ?? byDefault,
      (String key, T value) => _prefs.setString(key, value.name),
      notifyListeners,
    );
  }

  static const String _hiddenPatternsKey = 'hiddenThreadPatterns';

  late List<String> _hiddenPatterns = List<String>.unmodifiable(
    _prefs.getStringList(_hiddenPatternsKey) ?? const <String>[],
  );
  late List<RegExp> _hiddenRegexes = _compileAll(_hiddenPatterns);

  /// Thread filters: threads matching any of these aren't shown.
  List<String> get hiddenThreadPatterns => _hiddenPatterns;

  static List<RegExp> _compileAll(List<String> patterns) => [
    for (final String pattern in patterns) _compile(pattern),
  ];

  static RegExp _compile(String pattern) {
    try {
      return RegExp(pattern, caseSensitive: false);
    } on FormatException {
      return RegExp(RegExp.escape(pattern), caseSensitive: false);
    }
  }

  bool isThreadHidden(Post post) {
    if (_hiddenRegexes.isEmpty) {
      return false;
    }

    final String text = plainText('${post.sub ?? ''}\n${post.com ?? ''}');
    return _hiddenRegexes.any((RegExp filter) => filter.hasMatch(text));
  }

  /// Whether a board or the feed lists [post].
  bool isThreadListed(Post post) =>
      !isThreadHidden(post) && (showStickyThreads.value || !post.isSticky);

  Future<void> addHiddenThreadPattern(String pattern) async {
    final String trimmed = pattern.trim();
    if (trimmed.isNotEmpty && !_hiddenPatterns.contains(trimmed)) {
      await _setHiddenPatterns([..._hiddenPatterns, trimmed]);
    }
  }

  Future<void> removeHiddenThreadPattern(String pattern) async {
    if (_hiddenPatterns.contains(pattern)) {
      await _setHiddenPatterns([
        for (final String p in _hiddenPatterns)
          if (p != pattern) p,
      ]);
    }
  }

  Future<void> _setHiddenPatterns(List<String> patterns) async {
    _hiddenPatterns = List<String>.unmodifiable(patterns);
    _hiddenRegexes = _compileAll(_hiddenPatterns);
    notifyListeners();
    await _prefs.setStringList(_hiddenPatternsKey, patterns);
  }

  static const String _postFiltersKey = 'postFilters';

  late List<PostFilter> _postFilters =
      List<PostFilter>.unmodifiable(<PostFilter>[
        for (final String stored
            in _prefs.getStringList(_postFiltersKey) ?? const <String>[])
          ?PostFilter.parse(stored),
      ]);

  /// Filters that hide posts in every thread. A new list each time they change.
  List<PostFilter> get postFilters => _postFilters;

  Future<void> addPostFilter(PostFilter filter) async {
    if (filter.value.isNotEmpty && !_postFilters.contains(filter)) {
      await _setPostFilters([..._postFilters, filter]);
    }
  }

  Future<void> removePostFilter(PostFilter filter) async {
    if (_postFilters.contains(filter)) {
      await _setPostFilters([
        for (final PostFilter each in _postFilters)
          if (each != filter) each,
      ]);
    }
  }

  Future<void> _setPostFilters(List<PostFilter> filters) async {
    _postFilters = List<PostFilter>.unmodifiable(filters);
    notifyListeners();
    await _prefs.setStringList(_postFiltersKey, <String>[
      for (final PostFilter filter in filters) filter.stored,
    ]);
  }
}
