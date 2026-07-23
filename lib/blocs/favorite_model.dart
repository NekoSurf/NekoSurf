import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final favoritesProvider =
    NotifierProvider<FavoritesNotifier, FavoritesState>(FavoritesNotifier.new);

class FavoritesState {
  const FavoritesState({this.list = const []});

  final List<String> list;

  List<String> getFavorites() => list;

  FavoritesState copyWith({List<String>? list}) {
    return FavoritesState(list: list ?? this.list);
  }
}

class FavoritesNotifier extends Notifier<FavoritesState> {
  @override
  FavoritesState build() {
    _loadPreferences();
    return const FavoritesState();
  }

  Future<void> _loadPreferences() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    state = FavoritesState(list: prefs.getStringList('favoriteBoards') ?? []);
  }

  Future<void> addFavorites(String board) async {
    if (state.list.contains(board)) {
      return;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final updated = List<String>.from(state.list)..add(board);
    prefs.setStringList('favoriteBoards', updated);
    state = state.copyWith(list: updated);
  }

  Future<void> removeFavorites(String board) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final updated = List<String>.from(state.list)..remove(board);
    prefs.setStringList('favoriteBoards', updated);
    state = state.copyWith(list: updated);
  }
}
