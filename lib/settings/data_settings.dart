import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/history/history_model.dart';
import 'package:flutter_chan/history/watched_posts_model.dart';
import 'package:flutter_chan/media/image_cache.dart';
import 'package:flutter_chan/media/video_server.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/settings/settings_widgets.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_menu.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';
import 'package:flutter_chan/ui/toast.dart';
import 'package:provider/provider.dart';

class DataSettings extends StatefulWidget {
  const DataSettings({super.key});

  @override
  State<DataSettings> createState() => _DataSettingsState();
}

class _DataSettingsState extends State<DataSettings> {
  /// What the video cache takes up; null until measured.
  int? _videoCacheSize;

  /// What cached images take up; null until measured.
  int? _imageCacheSize;

  @override
  void initState() {
    super.initState();
    _measureVideoCache();
    _measureImageCache();
  }

  Future<void> _measureImageCache() async {
    final int size = await imageCacheSize();
    if (mounted) {
      setState(() => _imageCacheSize = size);
    }
  }

  Future<void> _measureVideoCache() async {
    final int size = await VideoServer.instance.cacheSize();
    if (mounted) {
      setState(() => _videoCacheSize = size);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final int? videoCacheSize = _videoCacheSize;
    final int? imageCacheSize = _imageCacheSize;

    return DashScaffold(
      title: 'Data',
      subtitle: 'Reading progress, history and caches',
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              SettingsGroup(
                title: 'Reading',
                children: [
                  SettingsRow(
                    icon: CupertinoIcons.arrow_down_circle_fill,
                    color: const Color(0xFF60A5FA),
                    title: 'Auto-scroll to last seen',
                    subtitle: 'Open threads where you left them',
                    trailing: SettingsSwitch(
                      value: settings.autoScrollToLastSeen.value,
                      onChanged: settings.autoScrollToLastSeen.set,
                    ),
                  ),
                ],
              ),
              SettingsGroup(
                title: 'Mobile data',
                footer:
                    'Threads show only thumbnails. Images and videos load when '
                    'you open them.',
                children: [
                  SettingsRow(
                    icon: CupertinoIcons.antenna_radiowaves_left_right,
                    color: const Color(0xFF34D399),
                    title: 'Data saver',
                    trailing: SettingsSwitch(
                      value: settings.dataSaver.value,
                      onChanged: settings.dataSaver.set,
                    ),
                  ),
                ],
              ),
              SettingsGroup(
                title: 'Saving',
                footer:
                    'Files you save or share are named by their number on '
                    '4chan, like 1700000000000.jpg, instead of what the poster '
                    'called them. Files already saved keep their names.',
                children: [
                  SettingsRow(
                    icon: CupertinoIcons.number_square_fill,
                    color: const Color(0xFFFBBF24),
                    title: "Use 4chan's file names",
                    trailing: SettingsSwitch(
                      value: settings.serverFileNames.value,
                      onChanged: settings.serverFileNames.set,
                    ),
                  ),
                ],
              ),
              SettingsGroup(
                title: 'Videos',
                footer:
                    'Watched videos are kept on your phone, so they start '
                    'instantly next time. Beyond the limit, the oldest are '
                    'deleted.',
                children: [
                  DashMenuAnchor(
                    menuChildren: [
                      for (final megabytes in [100, 300, 500, 1024])
                        DashMenuEntry(
                          title: _formatCacheSize(megabytes * megabyte),
                          icon: CupertinoIcons.film,
                          isSelected:
                              settings.videoCacheMegabytes.value == megabytes,
                          onPressed: () async {
                            await settings.videoCacheMegabytes.set(megabytes);
                            // Lowering it deletes the oldest videos.
                            await VideoServer.instance.setMaxCacheBytes(
                              megabytes * megabyte,
                            );
                            await _measureVideoCache();
                          },
                        ),
                    ],
                    builder: (context, open) => SettingsRow(
                      icon: CupertinoIcons.film_fill,
                      color: const Color(0xFFA78BFA),
                      title: 'Video cache limit',
                      value: _formatCacheSize(
                        settings.videoCacheMegabytes.value * megabyte,
                      ),
                      onTap: open,
                    ),
                  ),
                  _ClearRow(
                    icon: CupertinoIcons.trash_fill,
                    title: 'Clear video cache',
                    value: videoCacheSize == null
                        ? null
                        : _formatCacheSize(videoCacheSize),
                    done: 'Video cache cleared!',
                    clear: () async {
                      await VideoServer.instance.clearCache();
                      await _measureVideoCache();
                    },
                  ),
                ],
              ),
              SettingsGroup(
                title: 'Images',
                footer:
                    'Thumbnails and images you open are kept for a while, so '
                    'they show without downloading them again.',
                children: [
                  _ClearRow(
                    icon: CupertinoIcons.trash_fill,
                    title: 'Clear image cache',
                    value: imageCacheSize == null
                        ? null
                        : _formatCacheSize(imageCacheSize),
                    done: 'Image cache cleared!',
                    clear: () async {
                      await clearImageCache();
                      await _measureImageCache();
                    },
                  ),
                ],
              ),
              SettingsGroup(
                title: 'Storage',
                footer:
                    'Watched status of posts is kept for the selected number of days.',
                children: [
                  DashMenuAnchor(
                    menuChildren: [
                      for (final days in [3, 7, 14, 30])
                        DashMenuEntry(
                          title: '$days days',
                          icon: CupertinoIcons.clock,
                          isSelected:
                              settings.watchedPostsRetentionDays.value == days,
                          onPressed: () =>
                              settings.watchedPostsRetentionDays.set(days),
                        ),
                    ],
                    builder: (context, open) => SettingsRow(
                      icon: CupertinoIcons.timer,
                      color: const Color(0xFFFBBF24),
                      title: 'Watched posts retention',
                      value: '${settings.watchedPostsRetentionDays.value} days',
                      onTap: open,
                    ),
                  ),
                  _ClearRow(
                    icon: CupertinoIcons.eye_slash_fill,
                    title: 'Clear watched posts',
                    done: 'Watched posts history cleared!',
                    clear: Provider.of<WatchedPostsProvider>(
                      context,
                      listen: false,
                    ).clearAllWatchedPosts,
                  ),
                  _ClearRow(
                    icon: CupertinoIcons.clock_fill,
                    title: 'Clear recently visited',
                    done: 'Recent history cleared!',
                    clear: Provider.of<HistoryProvider>(
                      context,
                      listen: false,
                    ).clear,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A row that clears something away, and says so.
class _ClearRow extends StatelessWidget {
  const _ClearRow({
    required this.icon,
    required this.title,
    required this.done,
    required this.clear,
    this.value,
  });

  final IconData icon;
  final String title;
  final String? value;
  final String done;
  final Future<void> Function() clear;

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      icon: icon,
      color: DashColors.danger,
      title: title,
      value: value,
      destructive: true,
      onTap: () async {
        await clear();
        if (context.mounted) {
          showToast(context, done);
        }
      },
    );
  }
}

String _formatCacheSize(int bytes) {
  // Thumbnails are a few KB each; don't show a full cache as "0 MB".
  if (bytes < megabyte) {
    return '${(bytes / 1024).ceil()} KB';
  }
  if (bytes >= 1024 * megabyte) {
    final double gigabytes = bytes / (1024 * megabyte);
    return '${gigabytes.toStringAsFixed(gigabytes < 10 ? 1 : 0)} GB'
        .replaceFirst('.0 ', ' ');
  }
  return '${(bytes / megabyte).round()} MB';
}
