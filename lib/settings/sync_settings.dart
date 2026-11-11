import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/settings/settings_widgets.dart';
import 'package:flutter_chan/sync/cloud_sync.dart';
import 'package:flutter_chan/ui/app_restart.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_dialogs.dart';
import 'package:flutter_chan/ui/dash_menu.dart';
import 'package:flutter_chan/ui/frosted.dart';
import 'package:flutter_chan/ui/toast.dart';
import 'package:intl/intl.dart';

const String _whatSyncs =
    'saved media, bookmarks, history, read posts, favorite boards, filters '
    'and settings';

/// On launch, once per install: if iCloud has NekoSurf's data (from another
/// device, or before reinstalling) and sync is off here, offers to turn it
/// on. Until it's asked, each launch looks again, as the data may come
/// later, or iCloud couldn't say.
Future<void> offerCloudSyncOnLaunch(BuildContext context) async {
  final AppRestart? app = AppRestart.maybeOf(context);
  final CloudSync sync = CloudSync.instance;
  if (app == null ||
      !sync.supported ||
      sync.isOn ||
      sync.wasAsked(app.prefs) ||
      await sync.availability() != SyncAvailability.available ||
      await sync.hasCloudData() != true ||
      !context.mounted) {
    return;
  }
  await sync.markAsked(app.prefs);
  if (!context.mounted) {
    return;
  }
  final bool? turnOn = await showDashDialog<bool>(
    context: context,
    builder: (dialogContext) => DashDialog(
      title: const Text('Sync with iCloud?'),
      content: const Text(
        'Your iCloud has NekoSurf data from another device. Turn on iCloud '
        'sync to bring your $_whatSyncs here, and keep them the same on all '
        'your devices. You can turn it on later in Settings.',
      ),
      actions: [
        DashDialogAction(
          child: const Text('Not now'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        DashDialogAction(
          isDefaultAction: true,
          child: const Text('Turn on'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
  if ((turnOn ?? false) && context.mounted) {
    await _turnOn(context);
  }
}

Future<void> _turnOn(BuildContext context) async {
  String message = 'iCloud sync is on';
  try {
    await CloudSync.instance.turnOn();
    final int count = CloudSync.instance.lastBroughtIn;
    if (count > 0) {
      message = 'iCloud sync is on: ${_things(count)} brought in';
    }
  } on SyncFailed catch (e) {
    message = "Couldn't turn on iCloud sync. $e";
  }
  if (context.mounted) {
    showToast(context, message);
  }
}

String _things(int n) => n == 1 ? '1 thing' : '$n things';

/// While iCloud sync is being turned on, a pill above the tab bar saying
/// how far it's got, wherever in the app you are: saved media takes a while
/// to come down.
class CloudSyncProgress extends StatelessWidget {
  const CloudSyncProgress({super.key});

  @override
  Widget build(BuildContext context) {
    final CloudSync sync = CloudSync.instance;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final int count = sync.broughtIn;
        return IgnorePointer(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: !sync.joining
                ? const SizedBox.shrink()
                : Frosted(
                    radius: 999,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    color: Frosted.panel(context),
                    borderColor: context.accent.withValues(alpha: 0.25),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CupertinoActivityIndicator(radius: 8),
                        const SizedBox(width: 10),
                        Text(
                          count == 0
                              ? 'Bringing in from iCloud…'
                              : 'Bringing in from iCloud… ${_things(count)}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: DashColors.text(context),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }
}

String _ago(DateTime time) {
  final Duration since = DateTime.now().difference(time);
  if (since.inMinutes < 1) {
    return 'Just now';
  }
  if (since.inHours < 1) {
    return '${since.inMinutes} min ago';
  }
  final DateTime now = DateTime.now();
  final bool today =
      time.year == now.year && time.month == now.month && time.day == now.day;
  return today
      ? DateFormat.Hm().format(time)
      : DateFormat.MMMd().add_Hm().format(time);
}

/// Turning iCloud sync on and off, and how it's doing. Only on iPhone and
/// iPad.
class CloudSyncSettings extends StatefulWidget {
  const CloudSyncSettings({super.key});

  @override
  State<CloudSyncSettings> createState() => _CloudSyncSettingsState();
}

class _CloudSyncSettingsState extends State<CloudSyncSettings> {
  final CloudSync _sync = CloudSync.instance;
  Future<SyncAvailability>? _availability;
  bool _visible = false;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _sync.addListener(_changed);
  }

  @override
  void dispose() {
    _sync.removeListener(_changed);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The tab stays alive: look again whenever it comes back, as the
    // iCloud account may have changed meanwhile.
    final bool visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_visible && _sync.supported) {
      _availability = _sync.availability();
    }
    _visible = visible;
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _while(Future<void> Function() work) async {
    setState(() => _working = true);
    try {
      await work();
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _confirmTurnOn() async {
    final bool? turnOn = await showDashDialog<bool>(
      context: context,
      builder: (dialogContext) => DashDialog(
        title: const Text('Turn on iCloud sync?'),
        content: const Text(
          "What's on this phone is merged with what's in iCloud, and kept the "
          'same on all your devices with iCloud sync on. Saved media counts '
          'toward your iCloud storage.',
        ),
        actions: [
          DashDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          DashDialogAction(
            isDefaultAction: true,
            child: const Text('Turn on'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if ((turnOn ?? false) && mounted) {
      await _while(() => _turnOn(context));
    }
  }

  Future<void> _confirmTurnOff() async {
    final bool? delete = await showDashDialog<bool>(
      context: context,
      builder: (dialogContext) => DashDialog(
        title: const Text('Turn off iCloud sync?'),
        content: const Text(
          "This phone keeps everything it has. Keep NekoSurf's data in "
          'iCloud for your other devices, or delete it from iCloud, which '
          'turns iCloud sync off on all of them.',
        ),
        actions: [
          DashDialogAction(
            isDestructiveAction: true,
            child: const Text('Turn off and delete from iCloud'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
          DashDialogAction(
            isDefaultAction: true,
            child: const Text('Turn off, keep in iCloud'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
        ],
      ),
    );
    if (delete == null || !mounted) {
      return;
    }
    await _while(() async {
      String message = delete
          ? 'iCloud sync is off, and its data deleted from iCloud'
          : 'iCloud sync is off';
      try {
        await _sync.turnOff(deleteFromICloud: delete);
      } on SyncFailed catch (e) {
        message = "Couldn't delete NekoSurf's data from iCloud. $e";
      }
      if (mounted) {
        showToast(context, message);
      }
    });
  }

  Future<void> _confirmDelete() async {
    final bool? delete = await showDashDialog<bool>(
      context: context,
      builder: (dialogContext) => DashDialog(
        title: const Text("Delete NekoSurf's data from iCloud?"),
        content: const Text(
          'What iCloud sync keeps there is deleted, which turns it off on all '
          "your devices. What's on this phone stays.",
        ),
        actions: [
          DashDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          DashDialogAction(
            isDestructiveAction: true,
            child: const Text('Delete'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (!(delete ?? false) || !mounted) {
      return;
    }
    await _while(() async {
      String message = 'Deleted from iCloud';
      try {
        await _sync.deleteFromICloud();
      } on SyncFailed catch (e) {
        message = "Couldn't delete from iCloud. $e";
      }
      if (mounted) {
        showToast(context, message);
      }
    });
  }

  Future<void> _syncNow() async {
    await _while(() async {
      try {
        await _sync.syncNow();
      } on SyncFailed catch (e) {
        if (mounted) {
          showToast(context, "Couldn't sync. $e");
        }
      }
    });
  }

  Widget _row(SyncAvailability? availability) {
    const IconData icon = CupertinoIcons.cloud_fill;
    const Color color = Color(0xFF38BDF8);
    const String title = 'iCloud sync';
    final bool busy = _working || _sync.joining || _sync.status.syncing;
    final Widget? spinner = busy ? const CupertinoActivityIndicator() : null;

    if (!_sync.isOn) {
      final String? unavailable = switch (availability) {
        null => null,
        SyncAvailability.available || SyncAvailability.unknown => null,
        SyncAvailability.noAccount =>
          'Sign in to iCloud in the Settings app to keep your $_whatSyncs '
              'the same on all your devices.',
        SyncAvailability.notEntitled =>
          "Needs NekoSurf from TestFlight: sideloaded builds can't use "
              'iCloud. Back up to a file instead.',
      };
      if (unavailable != null) {
        return SettingsRow(
          icon: icon,
          color: color,
          title: title,
          subtitle: unavailable,
          value: 'Off',
        );
      }
      return DashMenuAnchor(
        menuChildren: [
          DashMenuEntry(
            title: 'Turn on iCloud sync',
            icon: CupertinoIcons.cloud,
            onPressed: _confirmTurnOn,
          ),
          DashMenuEntry(
            title: 'Delete NekoSurf data from iCloud',
            icon: CupertinoIcons.trash,
            isDestructive: true,
            onPressed: _confirmDelete,
          ),
        ],
        builder: (context, open) => SettingsRow(
          icon: icon,
          color: color,
          title: title,
          subtitle: _sync.joining
              ? 'Bringing in from iCloud… ${_things(_sync.broughtIn)}'
              : [
                  ?_sync.notice,
                  'Keep your $_whatSyncs the same on your iPhone and iPad.',
                ].join('\n\n'),
          value: _sync.joining ? null : 'Off',
          trailing: spinner,
          onTap: busy || availability == null ? null : open,
        ),
      );
    }

    final SyncStatus status = _sync.status;
    final DateTime? last = status.lastSynced;
    final String subtitle = switch (status.problem) {
      'quotaExceeded' =>
        "Your iCloud storage is full: what's changed here waits until "
            'there is room.',
      _ when _sync.joining =>
        'Bringing in from iCloud… ${_things(_sync.broughtIn)}',
      _ when status.syncing => 'Syncing…',
      _ when status.pending > 0 =>
        'Your $_whatSyncs, the same on all your devices. Changes made here '
            'go up when there is a connection.',
      _ =>
        'Your $_whatSyncs, the same on all your devices with iCloud sync '
            'on.',
    };
    return DashMenuAnchor(
      menuChildren: [
        DashMenuEntry(
          title: 'Sync now',
          icon: CupertinoIcons.arrow_2_circlepath,
          onPressed: _syncNow,
        ),
        DashMenuEntry(
          title: 'Turn off iCloud sync',
          icon: CupertinoIcons.xmark_circle,
          isDestructive: true,
          onPressed: _confirmTurnOff,
        ),
      ],
      builder: (context, open) => SettingsRow(
        icon: icon,
        color: color,
        title: title,
        subtitle: subtitle,
        value: busy ? null : (last == null ? 'On' : _ago(last)),
        trailing: spinner,
        onTap: _working || _sync.joining ? null : open,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_sync.supported) {
      return const SizedBox.shrink();
    }
    return SettingsGroup(
      title: 'iCloud sync',
      children: [
        FutureBuilder<SyncAvailability>(
          future: _availability,
          builder: (context, snapshot) => _row(snapshot.data),
        ),
      ],
    );
  }
}
