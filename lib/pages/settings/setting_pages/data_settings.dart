import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/blocs/history_model.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/blocs/watched_posts_model.dart';
import 'package:flutter_chan/pages/settings/settings_widgets.dart';
import 'package:flutter_chan/services/image_cache.dart';
import 'package:flutter_chan/services/show_snackbar.dart';
import 'package:flutter_chan/services/video_server.dart';
import 'package:flutter_chan/widgets/cupertino_menu.dart';
import 'package:flutter_chan/widgets/dash_dialogs.dart';
import 'package:flutter_chan/widgets/dash_scaffold.dart';
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
                    subtitle: 'Jump to the last media you viewed in a thread',
                    trailing: SettingsSwitch(
                      value: settings.getAutoScrollToLastSeen(),
                      onChanged: settings.setAutoScrollToLastSeen,
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
                        buildMenuItem(
                          title: formatCacheSize(megabytes * 1024 * 1024),
                          icon: CupertinoIcons.film,
                          isSelected:
                              settings.getVideoCacheMegabytes() == megabytes,
                          onPressed: () async {
                            // Lowering it deletes the oldest videos.
                            await settings.setVideoCacheMegabytes(megabytes);
                            await _measureVideoCache();
                          },
                        ),
                    ],
                    builder: (context, open) => SettingsRow(
                      icon: CupertinoIcons.film_fill,
                      color: const Color(0xFFA78BFA),
                      title: 'Video cache limit',
                      value: formatCacheSize(
                        settings.getVideoCacheMegabytes() * 1024 * 1024,
                      ),
                      onTap: open,
                    ),
                  ),
                  SettingsRow(
                    icon: CupertinoIcons.trash_fill,
                    color: const Color(0xFFFF5D6C),
                    title: 'Clear video cache',
                    value: videoCacheSize == null
                        ? null
                        : formatCacheSize(videoCacheSize),
                    destructive: true,
                    onTap: () async {
                      await VideoServer.instance.clearCache();
                      await _measureVideoCache();
                      if (context.mounted) {
                        showCupertinoSnackbar(
                          const Duration(milliseconds: 1800),
                          true,
                          context,
                          'Video cache cleared!',
                        );
                      }
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
                  SettingsRow(
                    icon: CupertinoIcons.trash_fill,
                    color: const Color(0xFFFF5D6C),
                    title: 'Clear image cache',
                    value: imageCacheSize == null
                        ? null
                        : formatCacheSize(imageCacheSize),
                    destructive: true,
                    onTap: () async {
                      await clearImageCache();
                      await _measureImageCache();
                      if (context.mounted) {
                        showCupertinoSnackbar(
                          const Duration(milliseconds: 1800),
                          true,
                          context,
                          'Image cache cleared!',
                        );
                      }
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
                        buildMenuItem(
                          title: '$days days',
                          icon: CupertinoIcons.clock,
                          isSelected:
                              settings.getWatchedPostsRetentionDays() == days,
                          onPressed: () =>
                              settings.setWatchedPostsRetentionDays(days),
                        ),
                    ],
                    builder: (context, open) => SettingsRow(
                      icon: CupertinoIcons.timer,
                      color: const Color(0xFFFBBF24),
                      title: 'Watched posts retention',
                      value: '${settings.getWatchedPostsRetentionDays()} days',
                      onTap: open,
                    ),
                  ),
                  SettingsRow(
                    icon: CupertinoIcons.eye_slash_fill,
                    color: const Color(0xFFFF5D6C),
                    title: 'Clear watched posts',
                    destructive: true,
                    onTap: () async {
                      await Provider.of<WatchedPostsProvider>(
                        context,
                        listen: false,
                      ).clearAllWatchedPosts();
                      if (context.mounted) {
                        showCupertinoSnackbar(
                          const Duration(milliseconds: 1800),
                          true,
                          context,
                          'Watched posts history cleared!',
                        );
                      }
                    },
                  ),
                  SettingsRow(
                    icon: CupertinoIcons.clock_fill,
                    color: const Color(0xFFFF5D6C),
                    title: 'Clear recently visited',
                    destructive: true,
                    onTap: () async {
                      await Provider.of<HistoryProvider>(
                        context,
                        listen: false,
                      ).clear();
                      if (context.mounted) {
                        showCupertinoSnackbar(
                          const Duration(milliseconds: 1800),
                          true,
                          context,
                          'Recent history cleared!',
                        );
                      }
                    },
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

String formatCacheSize(int bytes) {
  const int megabyte = 1024 * 1024;
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
