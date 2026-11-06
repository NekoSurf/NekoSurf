import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/chan/catalog.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/ui/dash_header.dart';
import 'package:flutter_chan/ui/dash_menu.dart';
import 'package:provider/provider.dart';

extension SortNames on Sort {
  String get title => switch (this) {
    Sort.byImagesCount => 'Image Count',
    Sort.byReplyCount => 'Reply Count',
    Sort.byBumpOrder => 'Bump Order',
    Sort.byNewest => 'Newest',
  };

  IconData get icon => switch (this) {
    Sort.byImagesCount => CupertinoIcons.photo,
    Sort.byReplyCount => CupertinoIcons.text_bubble,
    Sort.byBumpOrder => CupertinoIcons.arrow_up_arrow_down,
    Sort.byNewest => CupertinoIcons.clock,
  };
}

/// A page of threads with an order of its own, starting from the one in
/// Settings, and the menu to change that.
mixin ThreadOrder<T extends StatefulWidget> on State<T> {
  late Sort sort;
  late SortDirection sortDirection;

  /// The threads need sorting again.
  void onOrderChanged();

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    sort = settings.boardSort.value;
    sortDirection = settings.boardSortDirection.value;
  }

  Widget sortMenu(SettingsProvider settings) {
    return DashMenuButton(
      menuChildren: [
        for (final Sort option in Sort.values)
          DashMenuEntry(
            title: option.title,
            icon: option.icon,
            isSelected: sort == option,
            onPressed: () => setState(() {
              sort = option;
              onOrderChanged();
            }),
          ),
        const DashMenuDivider(),
        DashMenuEntry(
          title: 'Descending',
          icon: CupertinoIcons.arrow_down,
          isSelected: sortDirection == SortDirection.desc,
          onPressed: () => _setDirection(SortDirection.desc),
        ),
        DashMenuEntry(
          title: 'Ascending',
          icon: CupertinoIcons.arrow_up,
          isSelected: sortDirection == SortDirection.asc,
          onPressed: () => _setDirection(SortDirection.asc),
        ),
        const DashMenuDivider(),
        DashMenuEntry(
          title: 'Show Sticky Threads',
          icon: CupertinoIcons.pin,
          isSelected: settings.showStickyThreads.value,
          onPressed: () =>
              settings.showStickyThreads.set(!settings.showStickyThreads.value),
        ),
      ],
    );
  }

  void _setDirection(SortDirection direction) {
    setState(() {
      sortDirection = direction;
      onOrderChanged();
    });
  }
}

/// Switches pages of threads between the grid and the list.
class ViewModeButton extends StatelessWidget {
  const ViewModeButton({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final bool grid = settings.boardViewMode.value == ViewMode.grid;
    return DashIconButton(
      label: grid ? 'Show as list' : 'Show as grid',
      icon: Icon(
        grid ? CupertinoIcons.list_bullet : CupertinoIcons.square_grid_2x2,
      ),
      onPressed: () =>
          settings.boardViewMode.set(grid ? ViewMode.list : ViewMode.grid),
    );
  }
}
