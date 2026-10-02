import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/blocs/watched_posts_model.dart';
import 'package:flutter_chan/constants.dart';
import 'package:flutter_chan/widgets/cupertino_menu.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../../blocs/settings_model.dart';
import '../../../services/show_snackbar.dart';
import '../cupertino_settings_icon.dart';

class DataSettings extends StatefulWidget {
  const DataSettings({Key? key}) : super(key: key);

  @override
  State<DataSettings> createState() => DataSettingsState();
}

class DataSettingsState extends State<DataSettings> {
  double _cacheSize = 0.0;

  Future<void> getCacheSize() async {
    Directory applicationDocumentsDirectory;
    Directory temporaryDirectory;

    try {
      applicationDocumentsDirectory = await getApplicationDocumentsDirectory();
      temporaryDirectory = Directory(
        '${(await getTemporaryDirectory()).path}/libCachedImageData',
      );

      final List<FileSystemEntity> entitiesTemp = await temporaryDirectory
          .list()
          .toList();
      for (final entity in entitiesTemp) {
        if (entity is File) {
          setState(() {
            _cacheSize += getFileSize(entity);
          });
        }
      }

      final List<FileSystemEntity> entities =
          await applicationDocumentsDirectory.list().toList();
      for (final entity in entities) {
        if (entity is File) {
          print(entity.path);
          setState(() {
            _cacheSize += getFileSize(entity);
          });
        }
      }
    } catch (e) {
      print(e);
    }
  }

  double getFileSize(File file) {
    final int sizeInBytes = file.lengthSync();
    final double sizeInMb = sizeInBytes / (1024 * 1024);
    return sizeInMb;
  }

  Future<void> deleteCache() async {
    Directory applicationDocumentsDirectory;
    Directory temporaryDirectory;

    try {
      applicationDocumentsDirectory = await getApplicationDocumentsDirectory();
      temporaryDirectory = Directory(
        '${(await getTemporaryDirectory()).path}/libCachedImageData',
      );

      final List<FileSystemEntity> entitiesTemp = await temporaryDirectory
          .list()
          .toList();
      for (final entity in entitiesTemp) {
        if (entity is File) {
          await entity.delete();
        }
      }

      final List<FileSystemEntity> entities =
          await applicationDocumentsDirectory.list().toList();
      for (final entity in entities) {
        if (entity is File) {
          await entity.delete();
        }
      }

      showCupertinoSnackbar(
        const Duration(milliseconds: 1800),
        true,
        context,
        'Cache deleted!',
      );

      setState(() {
        _cacheSize = 0.0;
      });
    } catch (e) {
      print(e);
    }
  }

  @override
  void initState() {
    super.initState();

    getCacheSize();
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    return CupertinoPageScaffold(
      backgroundColor: AppColors.pageBackground(
        Theme.of(context).brightness == Brightness.dark,
      ),
      navigationBar: const CupertinoNavigationBar(middle: Text('Data')),
      child: ListView(
        children: [
          CupertinoListSection.insetGrouped(
            backgroundColor: Colors.transparent,
            children: [
              CupertinoListTile(
                leading: const CupertinoSettingsIcon(
                  icon: CupertinoIcons.arrow_down_circle,
                  color: CupertinoColors.systemBlue,
                ),
                title: const Text('Auto-scroll to last seen media'),
                subtitle: const Text(
                  'Automatically scroll to the last media you viewed',
                ),
                trailing: CupertinoSwitch(
                  onChanged: (value) => {
                    settings.setAutoScrollToLastSeen(value),
                  },
                  value: settings.getAutoScrollToLastSeen(),
                ),
              ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            backgroundColor: Colors.transparent,
            children: [
              CupertinoListTile(
                title: const Text('Cache Size'),
                trailing: Text(
                  '${_cacheSize.toStringAsFixed(2)} MB',
                  style: const TextStyle(color: CupertinoColors.systemGrey),
                ),
              ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            backgroundColor: Colors.transparent,
            children: [
              CupertinoListTile(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                leading: const CupertinoSettingsIcon(
                  color: CupertinoColors.systemRed,
                  icon: CupertinoIcons.trash,
                ),
                title: const Text('Delete Cache'),
                trailing: const CupertinoListTileChevron(),
                onTap: () => deleteCache(),
              ),
            ],
          ),

          CupertinoListSection.insetGrouped(
            backgroundColor: Colors.transparent,
            children: [
              CupertinoMenuAnchor(
                menuChildren: [
                  for (final days in [3, 7, 14, 30])
                    buildMenuItem(
                      title: '$days days',
                      icon: CupertinoIcons.clock,
                      isSelected:
                          settings.getWatchedPostsRetentionDays() == days,
                      onPressed: () =>
                          settings.setWatchedPostsRetentionDays(days),
                    ),
                ],
                builder: (context, controller, _) => CupertinoListTile(
                  title: const Text('Watched Posts Retention Period'),
                  subtitle: const Text(
                    'The number of days watched status of all posts will be kept.',
                  ),
                  trailing: Text(
                    '${settings.getWatchedPostsRetentionDays()} days',
                    style: const TextStyle(color: CupertinoColors.systemGrey),
                  ),
                  onTap: controller.open,
                ),
              ),

              CupertinoListTile(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                leading: const CupertinoSettingsIcon(
                  color: CupertinoColors.systemRed,
                  icon: CupertinoIcons.eye_slash,
                ),
                title: const Text('Clear Watched Posts History'),
                trailing: const CupertinoListTileChevron(),
                onTap: () async {
                  final watchedPostsProvider =
                      Provider.of<WatchedPostsProvider>(context, listen: false);
                  await watchedPostsProvider.clearAllWatchedPosts();
                  if (mounted) {
                    showCupertinoSnackbar(
                      const Duration(milliseconds: 1800),
                      true,
                      context,
                      'Watched posts history cleared!',
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
