import 'package:flutter/foundation.dart';
import 'package:flutter_chan/saved/saved_attachment.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/ui/pills.dart';

/// How the Saved tab is being looked through: what's shown, in what order, and
/// what's selected, by file name.
class SavedBrowsing with ChangeNotifier {
  SavedBrowsing(this._settings);

  final SettingsProvider _settings;

  bool selecting = false;
  final Set<String> selected = <String>{};

  MediaFilter filter = MediaFilter.all;

  bool get newestFirst => _settings.savedNewestFirst.value;

  void setFilter(MediaFilter value) {
    filter = value;
    notifyListeners();
  }

  void setNewestFirst(bool value) {
    _settings.savedNewestFirst.set(value);
    notifyListeners();
  }

  /// [attachments], oldest first, as they're shown.
  List<SavedAttachment> visible(List<SavedAttachment> attachments) {
    final List<SavedAttachment> items = attachments
        .where((a) => filter.shows(isVideo: a.isVideo))
        .toList();
    return newestFirst ? items.reversed.toList() : items;
  }

  void setSelecting(bool value) {
    selecting = value;
    selected.clear();
    notifyListeners();
  }

  void selectAll(List<SavedAttachment> shown) {
    selected
      ..clear()
      ..addAll(shown.map((a) => a.fileName));
    notifyListeners();
  }

  void deselectAll() {
    selected.clear();
    notifyListeners();
  }

  void toggleSelected(String fileName) {
    if (!selected.remove(fileName)) {
      selected.add(fileName);
    }
    notifyListeners();
  }
}
