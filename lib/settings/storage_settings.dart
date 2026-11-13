import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/media/image_cache.dart';
import 'package:flutter_chan/media/video_server.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/settings/settings_widgets.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/toast.dart';

/// What the app keeps on the phone to load faster, and clearing it.
class StorageSettings extends StatefulWidget {
  const StorageSettings({super.key});

  @override
  State<StorageSettings> createState() => _StorageSettingsState();
}

class _StorageSettingsState extends State<StorageSettings> {
  /// What cached videos and images take up; null until measured.
  int? _cacheSize;

  bool _visible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The tab stays alive, and browsing elsewhere fills the caches: measure
    // whenever it comes back.
    final bool visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_visible) {
      _measureCache();
    }
    _visible = visible;
  }

  Future<void> _measureCache() async {
    final List<int> sizes = await Future.wait([
      VideoServer.instance.cacheSize(),
      imageCacheSize(),
    ]);
    if (mounted) {
      setState(() => _cacheSize = sizes[0] + sizes[1]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final int? cacheSize = _cacheSize;

    return SettingsGroup(
      title: 'Storage',
      children: [
        _ClearRow(
          icon: CupertinoIcons.trash_fill,
          title: 'Clear cache',
          subtitle:
              'Videos, thumbnails and images you open are kept for a while, '
              'so they show without downloading them again.',
          value: cacheSize == null ? null : _formatCacheSize(cacheSize),
          done: 'Cache cleared!',
          clear: () async {
            await Future.wait([
              VideoServer.instance.clearCache(),
              clearImageCache(),
            ]);
            await _measureCache();
          },
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
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final String done;
  final Future<void> Function() clear;

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
