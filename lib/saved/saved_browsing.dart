import 'package:flutter/foundation.dart';
import 'package:flutter_chan/saved/saved_attachment.dart';

enum SavedFilter { all, images, videos }

/// How the Saved tab is being looked through: what's shown, in what order, and
/// what's selected, by file name.
class SavedBrowsing with ChangeNotifier {
  bool selecting = false;
  final Set<String> selected = <String>{};

  SavedFilter filter = SavedFilter.all;
  bool newestFirst = true;

  void setFilter(SavedFilter value) {
    filter = value;
    notifyListeners();
  }

  void setNewestFirst(bool value) {
    newestFirst = value;
    notifyListeners();
  }

  /// [attachments], oldest first, as they're shown.
  List<SavedAttachment> visible(List<SavedAttachment> attachments) {
    final List<SavedAttachment> items = attachments.where((a) {
      return switch (filter) {
        SavedFilter.all => true,
        SavedFilter.images => !a.isVideo,
        SavedFilter.videos => a.isVideo,
      };
    }).toList();
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
