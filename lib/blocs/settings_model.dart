import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);

class SettingsState {
  const SettingsState({
    this.allowNSFW = false,
    this.boardSort = Sort.byImagesCount,
    this.boardSortDirection = SortDirection.desc,
    this.boardViewMode = ViewMode.grid,
    this.watchedPostsRetentionDays = 7,
    this.autoScrollToLastSeen = false,
  });

  final bool allowNSFW;
  final Sort boardSort;
  final SortDirection boardSortDirection;
  final ViewMode boardViewMode;
  final int watchedPostsRetentionDays;
  final bool autoScrollToLastSeen;

  // Getter methods kept for backward compatibility with widget code.
  bool getNSFW() => allowNSFW;
  Sort getBoardSort() => boardSort;
  SortDirection getBoardSortDirection() => boardSortDirection;
  bool getAutoScrollToLastSeen() => autoScrollToLastSeen;
  int getWatchedPostsRetentionDays() => watchedPostsRetentionDays;
  ViewMode getBoardViewMode() => boardViewMode;

  SettingsState copyWith({
    bool? allowNSFW,
    Sort? boardSort,
    SortDirection? boardSortDirection,
    ViewMode? boardViewMode,
    int? watchedPostsRetentionDays,
    bool? autoScrollToLastSeen,
  }) {
    return SettingsState(
      allowNSFW: allowNSFW ?? this.allowNSFW,
      boardSort: boardSort ?? this.boardSort,
      boardSortDirection: boardSortDirection ?? this.boardSortDirection,
      boardViewMode: boardViewMode ?? this.boardViewMode,
      watchedPostsRetentionDays:
          watchedPostsRetentionDays ?? this.watchedPostsRetentionDays,
      autoScrollToLastSeen: autoScrollToLastSeen ?? this.autoScrollToLastSeen,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    _loadPreferences();
    return const SettingsState();
  }

  Future<void> _loadPreferences() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    Sort boardSort = Sort.byImagesCount;
    if (prefs.getString('boardSort') != null) {
      boardSort = Sort.values.firstWhere(
        (element) => element.name == prefs.getString('boardSort'),
      );
    }

    SortDirection boardSortDirection = SortDirection.desc;
    if (prefs.getString('boardSortDirection') != null) {
      boardSortDirection = SortDirection.values.firstWhere(
        (element) => element.name == prefs.getString('boardSortDirection'),
      );
    }

    final bool allowNSFW = prefs.getBool('allowNSFW') ?? false;

    await prefs.remove('useCachingOnVideos');

    final int watchedPostsRetentionDays =
        prefs.getInt('watchedPostsRetentionDays') ?? 7;

    final bool autoScrollToLastSeen =
        prefs.getBool('autoScrollToLastSeen') ?? false;

    ViewMode boardViewMode = ViewMode.grid;
    if (prefs.getString('boardViewMode') != null) {
      boardViewMode = ViewMode.values.firstWhere(
        (element) => element.name == prefs.getString('boardViewMode'),
        orElse: () => ViewMode.grid,
      );
    }

    await prefs.remove('inlineMediaInThreadFeed');

    state = SettingsState(
      allowNSFW: allowNSFW,
      boardSort: boardSort,
      boardSortDirection: boardSortDirection,
      boardViewMode: boardViewMode,
      watchedPostsRetentionDays: watchedPostsRetentionDays,
      autoScrollToLastSeen: autoScrollToLastSeen,
    );
  }

  Future<void> setNSFW(bool value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setBool('allowNSFW', value);
    state = state.copyWith(allowNSFW: value);
  }

  Future<void> setBoardSort(Sort sort) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString('boardSort', sort.name);
    state = state.copyWith(boardSort: sort);
  }

  Future<void> setBoardSortDirection(SortDirection direction) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString('boardSortDirection', direction.name);
    state = state.copyWith(boardSortDirection: direction);
  }

  Future<void> setAutoScrollToLastSeen(bool value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setBool('autoScrollToLastSeen', value);
    state = state.copyWith(autoScrollToLastSeen: value);
  }

  Future<void> setWatchedPostsRetentionDays(int days) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setInt('watchedPostsRetentionDays', days);
    state = state.copyWith(watchedPostsRetentionDays: days);
  }

  Future<void> setBoardViewMode(ViewMode mode) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString('boardViewMode', mode.name);
    state = state.copyWith(boardViewMode: mode);
  }
}
