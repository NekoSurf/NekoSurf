import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/history/history_model.dart';
import 'package:flutter_chan/history/watched_posts_model.dart';
import 'package:flutter_chan/media/image_cache.dart';
import 'package:flutter_chan/media/video_server.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/settings/settings_widgets.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_dialogs.dart';
import 'package:flutter_chan/ui/dash_menu.dart';
import 'package:flutter_chan/ui/toast.dart';
import 'package:provider/provider.dart';

/// What the app remembers on the phone, and clearing it.
class StorageSettings extends StatefulWidget {
  const StorageSettings({super.key});

  @override
  State<StorageSettings> createState() => _StorageSettingsState();
}

class _StorageSettingsState extends State<StorageSettings> {
  /// What the video cache takes up; null until measured.
  int? _videoCacheSize;

  /// What cached images take up; null until measured.
  int? _imageCacheSize;

  bool _visible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The tab stays alive, and browsing elsewhere fills the caches: measure
    // whenever it comes back.
    final bool visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_visible) {
      _measureVideoCache();
      _measureImageCache();
    }
    _visible = visible;
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

    return Column(
      children: [
        SettingsGroup(
          title: 'History',
          children: [
            SettingsRow(
              icon: CupertinoIcons.clock_fill,
              color: const Color(0xFF60A5FA),
              title: 'Track history',
              subtitle:
                  'List the threads you open on the History page. Turning this '
                  'off also clears what is stored.',
              trailing: SettingsSwitch(
                value: settings.trackHistory.value,
                onChanged: Provider.of<HistoryProvider>(
                  context,
                  listen: false,
                ).setTracking,
              ),
            ),
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
                title: 'Keep watched posts',
                subtitle: 'How long to remember which posts you have seen',
                value: '${settings.watchedPostsRetentionDays.value} days',
                onTap: open,
              ),
            ),
            _ClearRow(
              icon: CupertinoIcons.eye_slash_fill,
              title: 'Clear watched posts',
              done: 'Watched posts history cleared!',
              confirm:
                  'This forgets which posts you have seen, where you left off '
                  'and what you folded, in every thread.',
              clear: Provider.of<WatchedPostsProvider>(
                context,
                listen: false,
              ).clearAllWatchedPosts,
            ),
            _ClearRow(
              icon: CupertinoIcons.clock_fill,
              title: 'Clear recently visited',
              done: 'Recent history cleared!',
              confirm: 'This removes every thread from your History page.',
              clear: Provider.of<HistoryProvider>(context, listen: false).clear,
            ),
          ],
        ),
        SettingsGroup(
          title: 'Storage',
          children: [
            DashMenuAnchor(
              menuChildren: [
                for (final megabytes in [100, 300, 500, 1024])
                  DashMenuEntry(
                    title: _formatCacheSize(megabytes * megabyte),
                    icon: CupertinoIcons.film,
                    isSelected: settings.videoCacheMegabytes.value == megabytes,
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
                subtitle:
                    'Watched videos are kept so they start instantly next '
                    'time. Beyond the limit, the oldest are deleted.',
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
            _ClearRow(
              icon: CupertinoIcons.trash_fill,
              title: 'Clear image cache',
              subtitle:
                  'Thumbnails and images you open are kept for a while, so '
                  'they show without downloading them again.',
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
    this.subtitle,
    this.value,
    this.confirm,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final String done;
  final Future<void> Function() clear;

  /// What to warn about first, for what can't be got back by browsing again.
  final String? confirm;

  Future<bool> _confirmed(BuildContext context) async {
    final String? warning = confirm;
    if (warning == null) {
      return true;
    }
    final bool? confirmed = await showDashDialog<bool>(
      context: context,
      builder: (dialogContext) => DashDialog(
        title: Text('$title?'),
        content: Text(warning),
        actions: [
          DashDialogAction(
            isDefaultAction: true,
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          DashDialogAction(
            isDestructiveAction: true,
            child: const Text('Clear'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      icon: icon,
      color: DashColors.danger,
      title: title,
      subtitle: subtitle,
      value: value,
      destructive: true,
      onTap: () async {
        if (!await _confirmed(context)) {
          return;
        }
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
