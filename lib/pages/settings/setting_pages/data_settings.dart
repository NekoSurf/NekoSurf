import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/blocs/watched_media_model.dart';
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
          '${(await getTemporaryDirectory()).path}/libCachedImageData');

      final List<FileSystemEntity> entitiesTemp =
          await temporaryDirectory.list().toList();
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
          '${(await getTemporaryDirectory()).path}/libCachedImageData');

      final List<FileSystemEntity> entitiesTemp =
          await temporaryDirectory.list().toList();
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
    final theme = Provider.of<ThemeChanger>(context);
    final settings = Provider.of<SettingsProvider>(context);

    return CupertinoPageScaffold(
      backgroundColor: theme.getTheme() == ThemeData.dark()
          ? CupertinoColors.black
          : CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: theme.getTheme() == ThemeData.light()
            ? CupertinoColors.systemGroupedBackground.withOpacity(0.7)
            : CupertinoColors.black.withOpacity(0.7),
        brightness: theme.getTheme() == ThemeData.dark()
            ? Brightness.dark
            : Brightness.light,
        leading: MediaQuery(
          data: MediaQueryData(
            textScaleFactor: MediaQuery.textScaleFactorOf(context),
          ),
          child: Transform.translate(
            offset: const Offset(-16, 0),
            child: CupertinoNavigationBarBackButton(
              previousPageTitle: 'Settings',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
        border: Border.all(color: Colors.transparent),
        previousPageTitle: 'Settings',
        middle: MediaQuery(
          data: MediaQueryData(
            textScaleFactor: MediaQuery.textScaleFactorOf(context),
          ),
          child: Text(
            'Data',
            style: TextStyle(
              color: theme.getTheme() == ThemeData.dark()
                  ? Colors.white
                  : Colors.black,
            ),
          ),
        ),
      ),
      child: SafeArea(
          child: Column(
        children: [
          CupertinoListSection.insetGrouped(
            children: [
              CupertinoListTile(
                leading: const CupertinoSettingsIcon(
                  icon: CupertinoIcons.doc,
                  color: CupertinoColors.systemYellow,
                ),
                title: const Text(
                  'Use caching on videos (Experimental)',
                ),
                trailing: CupertinoSwitch(
                  onChanged: (value) => {
                    settings.setUseCachingOnVideos(value),
                  },
                  value: settings.getUseCachingOnVideos(),
                ),
              ),
              CupertinoListTile(
                leading: const CupertinoSettingsIcon(
                  icon: CupertinoIcons.arrow_down_circle,
                  color: CupertinoColors.systemBlue,
                ),
                title: const Text(
                  'Auto-scroll to last seen media',
                ),
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
            children: [
              CupertinoListTile(
                title: const Text('Cache Size'),
                trailing: Text(
                  '${_cacheSize.toStringAsFixed(2)} MB',
                  style: const TextStyle(
                    color: CupertinoColors.systemGrey,
                  ),
                ),
              ),
            ],
          ),
          CupertinoListSection.insetGrouped(children: [
            CupertinoListTile(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              leading: const CupertinoSettingsIcon(
                color: CupertinoColors.systemRed,
                icon: CupertinoIcons.trash,
              ),
              title: const Text('Delete Cache'),
              trailing: const CupertinoListTileChevron(),
              onTap: () => deleteCache(),
            )
          ]),
          CupertinoListSection.insetGrouped(
            children: [
              CupertinoListTile(
                title: const Text('Watched Media Retention Period'),
                subtitle: const Text(
                  'The number of days watched status of all media will be kept.',
                ),
                trailing: CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: Text(
                    '${settings.getWatchedMediaRetentionDays()} days',
                    style: const TextStyle(color: CupertinoColors.systemGrey),
                  ),
                  onPressed: () async {
                    final int? selected = await showCupertinoModalPopup<int>(
                      context: context,
                      builder: (context) {
                        return CupertinoActionSheet(
                          title: const Text('Select retention period'),
                          actions: [
                            for (final days in [3, 7, 14, 30])
                              CupertinoActionSheetAction(
                                onPressed: () {
                                  Navigator.pop(context, days);
                                },
                                child: Text('$days days'),
                              ),
                          ],
                          cancelButton: CupertinoActionSheetAction(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                        );
                      },
                    );
                    if (selected != null) {
                      await settings.setWatchedMediaRetentionDays(selected);
                    }
                  },
                ),
              ),
              CupertinoListTile(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                leading: const CupertinoSettingsIcon(
                  color: CupertinoColors.systemRed,
                  icon: CupertinoIcons.eye_slash,
                ),
                title: const Text('Clear Watched Media History'),
                trailing: const CupertinoListTileChevron(),
                onTap: () async {
                  final watchedMediaProvider =
                      Provider.of<WatchedMediaProvider>(context, listen: false);
                  await watchedMediaProvider.clearAllWatchedMedia();
                  if (mounted) {
                    showCupertinoSnackbar(
                      const Duration(milliseconds: 1800),
                      true,
                      context,
                      'Watched media history cleared!',
                    );
                  }
                },
              ),
            ],
          ),
        ],
      )),
    );
  }
}
