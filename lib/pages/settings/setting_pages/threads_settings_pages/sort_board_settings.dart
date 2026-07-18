import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/constants.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:liquid_glass_widgets/widgets/interactive/glass_button.dart';
import 'package:liquid_glass_widgets/widgets/surfaces/glass_app_bar.dart';
import 'package:liquid_glass_widgets/widgets/surfaces/glass_scaffold.dart';
import 'package:provider/provider.dart';

class SortBoardSettings extends StatefulWidget {
  const SortBoardSettings({Key? key}) : super(key: key);

  @override
  State<SortBoardSettings> createState() => SortBoardSettingsState();
}

class SortBoardSettingsState extends State<SortBoardSettings> {
  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    return GlassScaffold(
      backgroundColor: AppColors.pageBackground(
        Theme.of(context).brightness == Brightness.dark,
      ),
      appBar: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: GlassAppBar(
          title: Text(
            'Default board sort',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ),
          leading: GlassButton(
            icon: const Icon(CupertinoIcons.back),
            onTap: () => Navigator.of(context).pop(),
            width: 40,
            height: 40,
            iconSize: 20,
          ),
        ),
      ),
      extendBody: false,
      body: CupertinoListSection.insetGrouped(
        backgroundColor: Colors.transparent,
        header: const Text('Sort by'),
        children: [
          CupertinoListTile(
            title: const Text('Images Count'),
            trailing: settings.getBoardSort().name == 'byImagesCount'
                ? const Icon(CupertinoIcons.check_mark)
                : Container(),
            onTap: () => {settings.setBoardSort(Sort.byImagesCount)},
          ),
          CupertinoListTile(
            title: const Text('Reply Count'),
            trailing: settings.getBoardSort().name == 'byReplyCount'
                ? const Icon(CupertinoIcons.check_mark)
                : Container(),
            onTap: () => {settings.setBoardSort(Sort.byReplyCount)},
          ),
          CupertinoListTile(
            title: const Text('Bump Order'),
            trailing: settings.getBoardSort().name == 'byBumpOrder'
                ? const Icon(CupertinoIcons.check_mark)
                : Container(),
            onTap: () => {settings.setBoardSort(Sort.byBumpOrder)},
          ),
          CupertinoListTile(
            title: const Text('Newest'),
            trailing: settings.getBoardSort().name == 'byNewest'
                ? const Icon(CupertinoIcons.check_mark)
                : Container(),
            onTap: () => {settings.setBoardSort(Sort.byNewest)},
          ),
          CupertinoListTile(
            title: const Text('Oldest'),
            trailing: settings.getBoardSort().name == 'byOldest'
                ? const Icon(CupertinoIcons.check_mark)
                : Container(),
            onTap: () => {settings.setBoardSort(Sort.byOldest)},
          ),
        ],
      ),
    );
  }
}
