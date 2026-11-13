import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_chan/chan/board.dart';
import 'package:flutter_chan/chan/catalog.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/chan/post_text.dart';
import 'package:flutter_chan/sync/cloud_sync.dart';
import 'package:flutter_chan/sync/sync_items.dart';
import 'package:flutter_chan/thread/post_hiding.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int megabyte = 1024 * 1024;

/// Where [SettingsProvider.savedFilesHidden] is kept.
const String savedFilesHiddenKey = 'savedFilesHidden';

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
  Setting._(
    this._key,
    this._value,
    this._store,
    this._toStored,
    this._fromStored,
    this._provider,
  );

  final String _key;
  T _value;
  final Future<bool> Function(String key, T value) _store;
  final Object Function(T value) _toStored;
  final T? Function(Object? stored) _fromStored;
  final SettingsProvider _provider;

  T get value => _value;

  Future<void> set(T value) async {
    _value = value;
    _provider._changed(_key, _toStored(value));
    await _store(_key, value);
  }

  /// Takes the value stored as [stored] on another device, if it's one.
  Future<void> _applyStored(Object? stored) async {
    final T? value = _fromStored(stored);
    if (value == null || value == _value) {
      return;
    }
    _value = value;
    _provider._applied();
    await _store(_key, value);
  }
}

/// The setting [key], stored as [value], as iCloud sync keeps it; changed
/// at [changedAt], or long ago.
SyncItem settingSyncItem(String key, Object value, {DateTime? changedAt}) =>
    SyncItem(SyncKind.setting, key, {
      'value': value,
    }, modifiedAt: changedAt ?? DateTime.fromMillisecondsSinceEpoch(0));

/// A thread filter, as iCloud sync keeps it.
SyncItem threadFilterSyncItem(String pattern) =>
    SyncItem(SyncKind.threadFilter, pattern, {'pattern': pattern});

/// A post filter, as iCloud sync keeps it.
SyncItem postFilterSyncItem(PostFilter filter) =>
    SyncItem(SyncKind.postFilter, filter.stored, {'filter': filter.stored});

/// A setting is one line here; loading and storing it follow from that.
class SettingsProvider with ChangeNotifier implements SyncTarget {
  SettingsProvider(this._prefs, {CloudSync? sync})
    : _sync = sync ?? CloudSync.instance {
    // Settings that no longer exist.
    unawaited(_prefs.remove('useCachingOnVideos'));
    unawaited(_prefs.remove('inlineMediaInThreadFeed'));
    unawaited(_prefs.remove('watchedPostsRetentionDays'));
    unawaited(_prefs.remove('videoCacheMegabytes'));
    _sync.attach(this);
  }

  final SharedPreferences _prefs;
  final CloudSync _sync;

  /// The settings iCloud sync keeps the same on every device; not those
  /// that depend on the device, like how much it caches.
  static const Set<String> syncedKeys = <String>{
    'allowNSFW',
    'appearance',
    'themeColor',
    'boardSort',
    'boardSortDirection',
    'boardViewMode',
    'threadLayout',
    'autoScrollToLastSeen',
    'showStickyThreads',
    'feedVideosStartMuted',
    'trackHistory',
    'savedNewestFirst',
    'fullscreenAutoAdvance',
    'serverFileNames',
    'nsfwEachSession',
    'blurNsfwImages',
    'showSavedTab',
    'askBeforePhotos',
    'coverInAppSwitcher',
    'historyThisSessionOnly',
  };

  // Each setting, once it's been read (they're late).
  final Map<String, Setting<Object>> _byKey = <String, Setting<Object>>{};

  void _applied() => notifyListeners();

  void _changed(String key, Object stored) {
    notifyListeners();
    if (syncedKeys.contains(key)) {
      final DateTime now = DateTime.now();
      unawaited(_noteChangedAt(key, now));
      _sync.put(settingSyncItem(key, stored, changedAt: now));
    }
  }

  /// Where it's kept when each synced setting was last changed, here or
  /// on another device: which wins when two devices changed it.
  static const String changedAtKey = 'sync.settingsChangedAt';

  /// When the setting [key] was last changed, as kept in [prefs]; null if
  /// not since this was kept, as for one never changed.
  static DateTime? changedAt(SharedPreferences prefs, String key) {
    final int? at = _changedAts(prefs)[key];
    return at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
  }

  static Map<String, int> _changedAts(SharedPreferences prefs) {
    try {
      final Object? decoded = jsonDecode(prefs.getString(changedAtKey) ?? '{}');
      return decoded is Map
          ? <String, int>{
              for (final MapEntry<Object?, Object?> entry in decoded.entries)
                if (entry.key case final String key)
                  if (entry.value case final int at) key: at,
            }
          : <String, int>{};
    } on FormatException {
      return <String, int>{};
    }
  }

  Future<void> _noteChangedAt(String key, DateTime at) =>
      _noteChanged(_prefs, [key], at);

  static Future<void> _noteChanged(
    SharedPreferences prefs,
    Iterable<String> keys,
    DateTime at,
  ) async {
    final Map<String, int> all = _changedAts(prefs);
    for (final String key in keys) {
      all[key] = at.millisecondsSinceEpoch;
    }
    await prefs.setString(changedAtKey, jsonEncode(all));
  }

  /// Every setting in [prefs] was changed now, as when a backup's been
  /// restored: what's in it goes to iCloud over what's there.
  static Future<void> noteAllChanged(SharedPreferences prefs) =>
      _noteChanged(prefs, syncedKeys.where(prefs.containsKey), DateTime.now());

  @override
  void dispose() {
    _sync.detach(this);
    super.dispose();
  }

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

  /// NSFW boards show only once they're turned on with the flame on Boards,
  /// until the app is closed: that's kept in memory only ([nsfwSessionOn]).
  late final Setting<bool> nsfwEachSession = _bool('nsfwEachSession', false);

  /// Images from NSFW boards are covered until tapped.
  late final Setting<bool> blurNsfwImages = _bool('blurNsfwImages', false);

  /// Saved has a tab of its own; without, it opens from History.
  late final Setting<bool> showSavedTab = _bool('showSavedTab', true);

  /// Saved files are kept in the app's own folder, out of the Files app (or
  /// Android's Download folder). Changed by [moveSavedFiles], which moves
  /// them; this device's own (see isLocalPreference).
  late final Setting<bool> savedFilesHidden = _bool(savedFilesHiddenKey, false);

  /// Saving to Photos asks first, saying where it'll show up.
  late final Setting<bool> askBeforePhotos = _bool('askBeforePhotos', false);

  /// The app switcher shows the app blurred (iOS) or blank (Android). Read
  /// by the app's native side (AppDelegate.swift, MainActivity.kt) by this
  /// name.
  late final Setting<bool> coverInAppSwitcher = _bool(
    'coverInAppSwitcher',
    false,
  );

  /// History is only kept in memory, never stored or synced, and is
  /// forgotten when the app is left.
  late final Setting<bool> historyThisSessionOnly = _bool(
    'historyThisSessionOnly',
    false,
  );

  bool _nsfwSession = false;

  /// NSFW boards were turned on with the flame, for this session.
  bool get nsfwSessionOn => _nsfwSession;

  /// NSFW boards, their threads and images show: they're allowed, and, if
  /// only each session, turned on for this one.
  bool get showsNsfw =>
      allowNSFW.value && (!nsfwEachSession.value || _nsfwSession);

  void setNsfwSession(bool on) {
    if (on != _nsfwSession) {
      _nsfwSession = on;
      notifyListeners();
    }
  }

  /// Where the codes of 4chan's NSFW boards are kept, from the last board
  /// list, so they're known before it loads again (or offline).
  static const String nsfwBoardsKey = 'nsfwBoards';

  late Set<String> _nsfwBoards = <String>{
    ...?_prefs.getStringList(nsfwBoardsKey),
  };

  /// Notes which of [boards] are NSFW.
  void rememberBoards(List<Board> boards) {
    final Set<String> nsfw = <String>{
      for (final Board board in boards)
        if (board.isNsfw) board.board,
    };
    if (nsfw.isEmpty || setEquals(nsfw, _nsfwBoards)) {
      return;
    }
    _nsfwBoards = nsfw;
    notifyListeners();
    unawaited(_prefs.setStringList(nsfwBoardsKey, nsfw.toList()..sort()));
  }

  /// [board] is one of 4chan's NSFW boards, as far as is known.
  bool isNsfwBoard(String board) => _nsfwBoards.contains(board);

  /// [board]'s threads aren't shown: it's NSFW, and NSFW boards aren't.
  bool hidesBoard(String board) => !showsNsfw && isNsfwBoard(board);

  Setting<T> _keep<T extends Object>(Setting<T> setting) {
    _byKey[setting._key] = setting;
    return setting;
  }

  Setting<bool> _bool(String key, bool byDefault) => _keep(
    Setting<bool>._(
      key,
      _prefs.getBool(key) ?? byDefault,
      _prefs.setBool,
      (bool value) => value,
      (Object? stored) => stored is bool ? stored : null,
      this,
    ),
  );

  Setting<T> _enum<T extends Enum>(String key, List<T> values, T byDefault) {
    T? named(Object? name) =>
        values.where((T value) => value.name == name).firstOrNull;
    return _keep(
      Setting<T>._(
        key,
        named(_prefs.getString(key)) ?? byDefault,
        (String key, T value) => _prefs.setString(key, value.name),
        (T value) => value.name,
        named,
        this,
      ),
    );
  }

  @override
  Set<SyncKind> get syncKinds => const <SyncKind>{
    SyncKind.setting,
    SyncKind.threadFilter,
    SyncKind.postFilter,
  };

  @override
  Future<void> applySync(List<SyncChange> changes) async {
    List<String> patterns = _hiddenPatterns;
    List<PostFilter> filters = _postFilters;
    for (final SyncChange change in changes) {
      switch (change.kind) {
        case SyncKind.setting:
          final String? key = change.key;
          final Object? value = change.data['value'];
          if (change.deleted || key == null || !syncedKeys.contains(key)) {
            continue;
          }
          if (change.modifiedAt case final DateTime at) {
            await _noteChangedAt(key, at);
          }
          final Setting<Object>? setting = _byKey[key];
          if (setting != null) {
            await setting._applyStored(value);
          } else {
            // Not read yet: it reads this when it is.
            await _storeRaw(key, value);
          }
        case SyncKind.threadFilter:
          final String? pattern = change.data['pattern'] as String?;
          patterns = change.deleted
              ? [
                  for (final String each in patterns)
                    if (!change.isFor(each)) each,
                ]
              : [
                  ...patterns,
                  if (pattern != null && !patterns.contains(pattern)) pattern,
                ];
        case SyncKind.postFilter:
          final PostFilter? filter = PostFilter.parse(
            change.data['filter'] as String? ?? '',
          );
          filters = change.deleted
              ? [
                  for (final PostFilter each in filters)
                    if (!change.isFor(each.stored)) each,
                ]
              : [
                  ...filters,
                  if (filter != null && !filters.contains(filter)) filter,
                ];
        default:
          break;
      }
    }
    if (!listEquals(patterns, _hiddenPatterns)) {
      await _setHiddenPatterns(patterns);
    }
    if (!listEquals(filters, _postFilters)) {
      await _setPostFilters(filters);
    }
  }

  Future<void> _storeRaw(String key, Object? value) async {
    switch (value) {
      case bool():
        await _prefs.setBool(key, value);
      case int():
        await _prefs.setInt(key, value);
      case String():
        await _prefs.setString(key, value);
    }
  }

  /// Where the thread filters are kept in SharedPreferences.
  static const String hiddenPatternsKey = 'hiddenThreadPatterns';

  late List<String> _hiddenPatterns = List<String>.unmodifiable(
    _prefs.getStringList(hiddenPatternsKey) ?? const <String>[],
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
      _sync.put(threadFilterSyncItem(trimmed));
      await _setHiddenPatterns([..._hiddenPatterns, trimmed]);
    }
  }

  Future<void> removeHiddenThreadPattern(String pattern) async {
    if (_hiddenPatterns.contains(pattern)) {
      _sync.remove(SyncKind.threadFilter, pattern);
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
    await _prefs.setStringList(hiddenPatternsKey, patterns);
  }

  /// Where the post filters are kept in SharedPreferences.
  static const String postFiltersKey = 'postFilters';

  late List<PostFilter> _postFilters =
      List<PostFilter>.unmodifiable(<PostFilter>[
        for (final String stored
            in _prefs.getStringList(postFiltersKey) ?? const <String>[])
          ?PostFilter.parse(stored),
      ]);

  /// Filters that hide posts in every thread. A new list each time they change.
  List<PostFilter> get postFilters => _postFilters;

  Future<void> addPostFilter(PostFilter filter) async {
    if (filter.value.isNotEmpty && !_postFilters.contains(filter)) {
      _sync.put(postFilterSyncItem(filter));
      await _setPostFilters([..._postFilters, filter]);
    }
  }

  Future<void> removePostFilter(PostFilter filter) async {
    if (_postFilters.contains(filter)) {
      _sync.remove(SyncKind.postFilter, filter.stored);
      await _setPostFilters([
        for (final PostFilter each in _postFilters)
          if (each != filter) each,
      ]);
    }
  }

  Future<void> _setPostFilters(List<PostFilter> filters) async {
    _postFilters = List<PostFilter>.unmodifiable(filters);
    notifyListeners();
    await _prefs.setStringList(postFiltersKey, <String>[
      for (final PostFilter filter in filters) filter.stored,
    ]);
  }
}
