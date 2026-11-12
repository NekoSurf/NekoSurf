import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chan/sync/sync_items.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps some of what's on this device (see [SyncKind]), and applies what
/// other devices changed of it.
abstract interface class SyncTarget {
  /// What it keeps.
  Set<SyncKind> get syncKinds;

  /// Applies [changes] made elsewhere, of [syncKinds], without telling
  /// [CloudSync] of them as changes made here.
  Future<void> applySync(List<SyncChange> changes);
}

/// iCloud sync didn't work; [code] says why (see the Swift side).
class SyncFailed implements Exception {
  const SyncFailed(this.code);

  final String code;

  @override
  String toString() => switch (code) {
    'noAccount' => 'Sign in to iCloud in the Settings app first.',
    'quotaExceeded' => 'Your iCloud storage is full.',
    'offline' => "Couldn't reach iCloud. Check your connection and try again.",
    'notEntitled' => "This build of NekoSurf can't use iCloud.",
    _ => 'Something went wrong with iCloud. Try again in a moment.',
  };
}

/// Whether this device can sync with iCloud.
enum SyncAvailability {
  available,

  /// Not signed in to iCloud, or iCloud is restricted.
  noAccount,

  /// A build signed without iCloud, as sideloaded ones are.
  notEntitled,

  /// iCloud couldn't say just now.
  unknown,
}

/// What iCloud sync is doing, as the Swift side says.
class SyncStatus {
  const SyncStatus({
    this.syncing = false,
    this.lastSynced,
    this.problem,
    this.error,
    this.pending = 0,
    this.pendingMedia = 0,
    this.uploadProgress,
    this.uploadBytes,
    this.uploadKey,
    this.pendingFileKeys = const <String>{},
    this.uploadProgresses = const <String, double>{},
    this.downloadId,
    this.downloadProgress,
    this.downloadIds = const <String>{},
  });

  factory SyncStatus.fromChannel(Map<Object?, Object?> map) {
    final num? last = map['lastSynced'] as num?;
    return SyncStatus(
      syncing: map['syncing'] == true,
      lastSynced: last == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(last.toInt()),
      problem: map['problem'] as String?,
      error: map['error'] as String?,
      pending: (map['pending'] as num?)?.toInt() ?? 0,
      pendingMedia: (map['pendingMedia'] as num?)?.toInt() ?? 0,
      uploadProgress: (map['uploadProgress'] as num?)?.toDouble(),
      uploadBytes: (map['uploadBytes'] as num?)?.toInt(),
      uploadKey: map['uploadKey'] as String?,
      pendingFileKeys: <String>{
        for (final Object? key in map['pendingFileKeys'] as List? ?? const [])
          if (key is String) key,
      },
      uploadProgresses: <String, double>{
        for (final MapEntry<Object?, Object?> entry
            in (map['uploadProgresses'] as Map? ?? const {}).entries)
          if (entry.key case final String key)
            if (entry.value case final num progress) key: progress.toDouble(),
      },
      downloadId: map['downloadId'] as String?,
      downloadProgress: (map['downloadProgress'] as num?)?.toDouble(),
      downloadIds: <String>{
        for (final Object? id in map['downloadIds'] as List? ?? const [])
          if (id is String) id,
      },
    );
  }

  final bool syncing;
  final DateTime? lastSynced;

  /// Why changes can't go out now: "quotaExceeded", or "failed" when
  /// iCloud refused them (see [error]).
  final String? problem;

  /// What iCloud said when it refused a change.
  final String? error;

  /// Changes made here that iCloud hasn't confirmed yet, and how many of
  /// them are saved files, which take a while to go up.
  final int pending;
  final int pendingMedia;

  /// How far the saved file going up now is (0 to 1), and its size; null
  /// when none is.
  final double? uploadProgress;
  final int? uploadBytes;

  /// The saved file going up now, and those that aren't in iCloud yet, by
  /// their keys (a saved attachment's id).
  final String? uploadKey;
  final Set<String> pendingFileKeys;

  /// How far each saved file going up is, by its key: several go at once
  /// once the app's left.
  final Map<String, double> uploadProgresses;

  /// The saved file coming down now, by its record's id, and how far it
  /// is (0 to 1); and those waiting to.
  final String? downloadId;
  final double? downloadProgress;
  final Set<String> downloadIds;
}

/// A saved file iCloud doesn't have yet: waiting its turn to go up, or
/// going up, [progress] (0 to 1) of the way.
class FileUpload {
  const FileUpload([this.progress]);

  final double? progress;
}

/// A saved file from another device that isn't here yet: waiting its turn
/// to come down, or coming down, [progress] (0 to 1) of the way.
class FileDownload {
  const FileDownload([this.progress]);

  final double? progress;
}

/// Says when saved files may have gone up to iCloud from other devices.
class _Signal extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// Keeps saved media, bookmarks, history, favorite boards, filters and
/// settings the same on every device with it on, through CloudKit (see
/// ios/Runner/CloudSync.swift). Only on iPhone and iPad, and off until
/// turned on ([turnOn]).
///
/// What's kept reports each change ([put], [remove]); what other devices
/// changed is applied by [SyncTarget]s, once all of them are there (not
/// while the app is restarted).
///
/// Turning it on merges this device with what's in iCloud: what's there is
/// applied here first, then everything here that it didn't have goes up.
class CloudSync extends ChangeNotifier {
  CloudSync._({required bool supported}) : _supported = supported;

  /// As on iPhone, with what's stored listed by [storedItems].
  @visibleForTesting
  CloudSync.forTesting(this.storedItems) : _supported = true;

  static final CloudSync instance = CloudSync._(supported: Platform.isIOS);

  static const MethodChannel _channel = MethodChannel('nekosurf/cloudsync');

  // This install's own: never backed up (see isLocalPreference).
  static const String onKey = 'sync.iCloud';
  static const String _joinedKey = 'sync.joined';
  static const String _askedKey = 'sync.asked';
  static const String _checkedKey = 'sync.checkedICloud';

  final bool _supported;

  /// Everything kept in sync, as it's stored in prefs now. It's of every
  /// feature, which all depend on this: main.dart sets it, to
  /// settings/synced_items.dart's.
  late Future<List<SyncItem>> Function(SharedPreferences prefs) storedItems;

  SharedPreferences? _prefs;
  final List<SyncTarget> _targets = <SyncTarget>[];
  Completer<void>? _targetsThere;
  final Map<String, SyncItem> _puts = <String, SyncItem>{};
  final Set<String> _deletes = <String>{};
  bool _flushScheduled = false;
  Future<void> _flushed = Future<void>.value();
  Future<void> _inbox = Future<void>.value();
  Set<String>? _receivedWhileJoining;
  bool _joining = false;
  SyncStatus _status = const SyncStatus();
  String? _notice;
  ({String title, String message})? _alert;
  bool _noticeSeen = true;

  /// Whether this device can have iCloud sync at all: iPhone and iPad.
  bool get supported => _supported;

  bool get isOn => _supported && (_prefs?.getBool(onKey) ?? false);

  /// Being turned on: what's in iCloud is coming in.
  bool get joining => _joining;

  /// How many things have come in from iCloud since it was turned on, while
  /// [joining].
  int get broughtIn => _receivedWhileJoining?.length ?? 0;

  /// How many things came in from iCloud the last time it was turned on.
  int get lastBroughtIn => _lastBroughtIn;
  int _lastBroughtIn = 0;

  SyncStatus get status => _status;

  /// Notifies when saved files may have gone up from other devices since:
  /// iCloud said so, or Sync now or coming back to the app fetched. A
  /// file can be there before its record says so, as its device goes on
  /// uploading after it's left.
  Listenable get filesMayHaveCome => _filesMayHaveCome;
  final _Signal _filesMayHaveCome = _Signal();

  /// How the saved file of [key] (its attachment id) stands with iCloud:
  /// null if it's there, or sync is off.
  FileUpload? fileUpload(String key) {
    if (!isOn) {
      return null;
    }
    if (_status.uploadProgresses[key] case final double progress) {
      return FileUpload(progress);
    }
    if (_status.uploadKey == key) {
      return FileUpload(_status.uploadProgress ?? 0);
    }
    return _status.pendingFileKeys.contains(key) ? const FileUpload() : null;
  }

  /// How the saved file of [key] (its attachment id), saved on another
  /// device, is coming down: null if it isn't, or sync is off.
  FileDownload? fileDownload(String key) {
    if (!isOn) {
      return null;
    }
    final String id = syncId(SyncKind.saved, key);
    if (_status.downloadId == id) {
      return FileDownload(_status.downloadProgress ?? 0);
    }
    return _status.downloadIds.contains(id) ? const FileDownload() : null;
  }

  /// Downloads the saved files of [keys] (attachment ids), whose records
  /// came without them, of those that are in iCloud; each comes in as a
  /// change of its own ([SyncChange.fileOnly]).
  Future<void> downloadFiles(Iterable<String> keys) async {
    final List<String> ids = <String>[
      for (final String key in keys) syncId(SyncKind.saved, key),
    ];
    if (!isOn || ids.isEmpty) {
      return;
    }
    try {
      await _invoke('download', ids);
    } on SyncFailed catch (e) {
      debugPrint('iCloud sync could not download saved files: $e');
    }
  }

  /// Why iCloud sync turned itself off, if it did since launch.
  String? get notice => _notice;

  /// Whether the Settings tab should show a dot: iCloud is full or refused
  /// a change, or sync turned itself off and Settings hasn't been looked
  /// at since.
  bool get needsAttention =>
      (isOn && _status.problem != null) || (_notice != null && !_noticeSeen);

  /// The Settings tab was looked at.
  void markNoticeSeen() {
    if (!_noticeSeen) {
      _noticeSeen = true;
      notifyListeners();
    }
  }

  /// Something to tell once, wherever in the app you are: sync stopped, or
  /// can't send what changed. Null once it's been taken.
  ({String title, String message})? takeAlert() {
    final ({String title, String message})? alert = _alert;
    _alert = null;
    return alert;
  }

  /// Whether iCloud sync was offered on launch, or turned on or off.
  bool wasAsked(SharedPreferences prefs) => prefs.getBool(_askedKey) ?? false;

  Future<void> markAsked(SharedPreferences prefs) =>
      prefs.setBool(_askedKey, true);

  /// Starts syncing, if it's on, with what's kept in [prefs].
  Future<void> load(SharedPreferences prefs) async {
    _prefs = prefs;
    if (!_supported) {
      return;
    }
    _channel.setMethodCallHandler(_onCall);
    if (!isOn) {
      return;
    }
    try {
      await _invoke('start');
      _status = SyncStatus.fromChannel(
        await _invoke('status') as Map<Object?, Object?>? ?? const {},
      );
      notifyListeners();
    } on SyncFailed catch (e) {
      debugPrint('iCloud sync could not start: $e');
      return;
    }
    await _resume();
  }

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'inbox':
        unawaited(processInbox());
      case 'filesChanged':
        _filesMayHaveCome.ping();
      case 'status':
        final String? was = _status.problem;
        _status = SyncStatus.fromChannel(
          call.arguments as Map<Object?, Object?>? ?? const {},
        );
        if (isOn && _status.problem != was) {
          _alert = switch (_status.problem) {
            'quotaExceeded' => (
              title: 'iCloud storage is full',
              message:
                  "What's changed on this device can't go to iCloud until "
                  'there is room: free up iCloud storage, or get more in the '
                  'Settings app, then tap iCloud sync › Sync now.',
            ),
            'failed' => (
              title: "iCloud didn't take a change",
              message:
                  "Something changed on this device that iCloud wouldn't "
                  'save, so your other devices may not have it. It is tried '
                  'again with iCloud sync › Sync now, and whenever NekoSurf '
                  'opens. iCloud said: ${_status.error ?? 'nothing more'}',
            ),
            _ => _alert,
          };
        }
        notifyListeners();
    }
    return null;
  }

  Future<Object?> _invoke(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on PlatformException catch (e) {
      throw SyncFailed(e.code);
    } on MissingPluginException {
      throw const SyncFailed('notEntitled');
    }
  }

  /// Whether this device can sync with iCloud now.
  Future<SyncAvailability> availability() async {
    if (!_supported) {
      return SyncAvailability.notEntitled;
    }
    try {
      final Map<Object?, Object?> answer =
          await _invoke('available') as Map<Object?, Object?>? ?? const {};
      if (answer['entitled'] != true) {
        return SyncAvailability.notEntitled;
      }
      return switch (answer['account']) {
        'available' => SyncAvailability.available,
        'noAccount' || 'restricted' => SyncAvailability.noAccount,
        _ => SyncAvailability.unknown,
      };
    } on SyncFailed catch (e) {
      return e.code == 'notEntitled'
          ? SyncAvailability.notEntitled
          : SyncAvailability.unknown;
    }
  }

  /// Whether iCloud has NekoSurf's data from another device (or an earlier
  /// install); null if it can't tell now.
  Future<bool?> hasCloudData() async {
    if (!_supported) {
      return false;
    }
    try {
      return await _invoke('hasCloudData') as bool?;
    } on SyncFailed {
      return null;
    }
  }

  // Changes made here.

  /// [item] changed here (or is new).
  void put(SyncItem item) => putAll(<SyncItem>[item]);

  void putAll(Iterable<SyncItem> items) {
    if (!isOn) {
      return;
    }
    for (final SyncItem item in items) {
      _deletes.remove(item.id);
      _puts[item.id] = item;
    }
    _scheduleFlush();
  }

  /// [key] of [kind] is gone here.
  void remove(SyncKind kind, String key) => removeAll(kind, <String>[key]);

  void removeAll(SyncKind kind, Iterable<String> keys) {
    if (!isOn) {
      return;
    }
    for (final String key in keys) {
      final String id = syncId(kind, key);
      _puts.remove(id);
      _deletes.add(id);
    }
    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (_flushScheduled) {
      return;
    }
    _flushScheduled = true;
    scheduleMicrotask(() => unawaited(_flush()));
  }

  /// Hands what changed here to the Swift side, a batch at a time: each
  /// call there runs on its own, so a removal and adding it back, handed
  /// over together, could arrive the other way round.
  Future<void> _flush() =>
      _flushed = _flushed.then((_) => _send()).catchError((Object e) {
        debugPrint('iCloud sync could not take changes: $e');
      });

  Future<void> _send() async {
    _flushScheduled = false;
    final List<Map<String, Object?>> puts = <Map<String, Object?>>[
      for (final SyncItem item in _puts.values) item.toChannel(),
    ];
    final List<String> deletes = _deletes.toList();
    _puts.clear();
    _deletes.clear();
    try {
      if (deletes.isNotEmpty) {
        await _invoke('delete', deletes);
      }
      if (puts.isNotEmpty) {
        await _invoke('save', puts);
      }
    } on SyncFailed catch (e) {
      debugPrint('iCloud sync could not take changes: $e');
    }
  }

  // Changes made elsewhere.

  void attach(SyncTarget target) {
    _targets.add(target);
    if (_allTargetsThere) {
      _targetsThere?.complete();
      _targetsThere = null;
    }
    if (isOn) {
      unawaited(_resume());
    }
  }

  void detach(SyncTarget target) => _targets.remove(target);

  bool get _allTargetsThere => <SyncKind>{
    for (final SyncTarget target in _targets) ...target.syncKinds,
  }.containsAll(SyncKind.values);

  /// Done once every [SyncTarget] is there to apply what comes in: not
  /// while the app is being built, or rebuilt after a restore.
  Future<void> _whenTargetsThere() {
    if (_allTargetsThere) {
      return Future<void>.value();
    }
    return (_targetsThere ??= Completer<void>()).future;
  }

  /// Goes on where it was: joins, if it was turned on and the app stopped
  /// before it was done, or applies what came in.
  Future<void> _resume() async {
    if (_joining || !_allTargetsThere) {
      return;
    }
    if (_prefs?.getBool(_joinedKey) ?? false) {
      await processInbox();
      if (!(_prefs?.getBool(_checkedKey) ?? false)) {
        unawaited(_checkICloudOnce());
      }
      return;
    }
    _joining = true;
    notifyListeners();
    try {
      await _join();
    } on SyncFailed catch (e) {
      debugPrint('iCloud sync could not join: $e');
    } finally {
      _joining = false;
      notifyListeners();
    }
  }

  /// Applies what other devices changed, once every [SyncTarget] is there.
  Future<void> processInbox() =>
      _inbox = _inbox.then((_) => _drainInbox()).catchError((Object e) {
        debugPrint('iCloud sync could not apply changes: $e');
      });

  Future<void> _drainInbox() async {
    while (isOn && _allTargetsThere) {
      final List<Object?> entries =
          await _invoke('takeInbox') as List<Object?>? ?? const [];
      if (entries.isEmpty) {
        return;
      }
      int last = -1;
      final List<SyncChange> changes = <SyncChange>[];
      for (final Object? entry in entries) {
        final Map<Object?, Object?> map = entry! as Map<Object?, Object?>;
        last = max(last, (map['seq']! as num).toInt());
        final String? event = map['event'] as String?;
        if (event != null) {
          await _apply(changes);
          changes.clear();
          if (await _onEvent(event)) {
            return;
          }
          continue;
        }
        final SyncChange? change = SyncChange.fromChannel(map);
        if (change != null) {
          changes.add(change);
          _receivedWhileJoining?.add(change.id);
        }
      }
      await _apply(changes);
      await _invoke('ackInbox', last);
      if (_receivedWhileJoining != null) {
        notifyListeners();
      }
    }
  }

  Future<void> _apply(List<SyncChange> changes) async {
    if (changes.isEmpty) {
      return;
    }
    for (final SyncTarget target in List<SyncTarget>.of(_targets)) {
      final List<SyncChange> its = <SyncChange>[
        for (final SyncChange change in changes)
          if (target.syncKinds.contains(change.kind)) change,
      ];
      if (its.isEmpty) {
        continue;
      }
      try {
        await target.applySync(its);
      } catch (e) {
        debugPrint('Applying iCloud changes failed: $e');
      }
    }
  }

  /// Handles [event] from the Swift side; whether it turned sync off.
  Future<bool> _onEvent(String event) async {
    switch (event) {
      case 'signedIn':
        // A sync engine without saved state (as when it's just been turned
        // on) says so too. Joining sends what's here once what's in iCloud
        // is applied; sent before, it would replace that.
        if (!_joining && (_prefs?.getBool(_joinedKey) ?? false)) {
          await _pushEverything();
        }
        return false;
      case 'signedOut':
        await _turnedOff(
          'iCloud sync turned off: this device signed out of iCloud, or '
              'into another account.',
          'This device signed out of iCloud, or into another account. '
              'Everything on it stays; turn iCloud sync on again in Settings '
              'once you are signed in.',
        );
        return true;
      case 'zoneDeleted':
        await _turnedOff(
          "iCloud sync turned off: NekoSurf's data was deleted from iCloud, "
              'on another device or in Settings.',
          "NekoSurf's data was deleted from iCloud, on another device or in "
              'Settings. Everything on this device stays; turn iCloud sync on '
              'again in Settings to start over from it.',
        );
        return true;
    }
    return false;
  }

  Future<void> _turnedOff(String notice, String alert) async {
    _notice = notice;
    _noticeSeen = false;
    _alert = (title: 'iCloud sync is off', message: alert);
    await _setOff();
    try {
      await _invoke('stop', <String, Object>{'delete': false});
    } on SyncFailed {
      // Stopped as far as it goes.
    }
    notifyListeners();
  }

  Future<void> _setOff() async {
    final SharedPreferences prefs = _prefs!;
    await prefs.setBool(onKey, false);
    await prefs.setBool(_joinedKey, false);
    _puts.clear();
    _deletes.clear();
    _status = const SyncStatus();
  }

  // Turning it on and off.

  /// Turns iCloud sync on: brings in what's in iCloud, then sends what's
  /// here that it didn't have. Throws [SyncFailed], and stays off, if
  /// iCloud can't be reached.
  Future<void> turnOn() async {
    final SharedPreferences prefs = _prefs!;
    _joining = true;
    _notice = null;
    notifyListeners();
    try {
      await _invoke('start');
      await markAsked(prefs);
      await prefs.setBool(onKey, true);
      await prefs.setBool(_joinedKey, false);
      await _join();
    } on SyncFailed {
      await _setOff();
      try {
        await _invoke('stop', <String, Object>{'delete': false});
      } on SyncFailed {
        // Off as far as it goes.
      }
      rethrow;
    } finally {
      _joining = false;
      notifyListeners();
    }
  }

  Future<void> _join() async {
    // What's here goes up only once what came in is applied: until then,
    // it could replace what's in iCloud with what this device had before.
    await _whenTargetsThere();
    final Set<String> received = _receivedWhileJoining = <String>{};
    try {
      await _invoke('fetch');
      await processInbox();
      await _pushEverything(except: received);
      await _prefs!.setBool(_joinedKey, true);
      unawaited(_invoke('send').catchError((Object _) => null));
    } finally {
      _lastBroughtIn = received.length;
      _receivedWhileJoining = null;
    }
  }

  /// Sends everything that's here, but what's in [except].
  Future<void> _pushEverything({Set<String> except = const {}}) async {
    putAll(<SyncItem>[
      for (final SyncItem item in await snapshot())
        if (!except.contains(item.id)) item,
    ]);
    await _flush();
  }

  /// Everything kept in sync, as it's stored here now.
  Future<List<SyncItem>> snapshot() => storedItems(_prefs!);

  /// Sends what changed in what's stored since [before] (a [snapshot]),
  /// as after restoring a backup.
  Future<void> pushChangesSince(List<SyncItem> before) async {
    if (!isOn) {
      return;
    }
    final Map<String, SyncItem> after = <String, SyncItem>{
      for (final SyncItem item in await snapshot()) item.id: item,
    };
    final Map<String, SyncItem> was = <String, SyncItem>{
      for (final SyncItem item in before) item.id: item,
    };
    putAll(<SyncItem>[
      for (final SyncItem item in after.values)
        if (!mapEquals(was[item.id]?.data, item.data)) item,
    ]);
    for (final SyncItem item in before) {
      if (!after.containsKey(item.id)) {
        _puts.remove(item.id);
        _deletes.add(item.id);
      }
    }
    await _flush();
  }

  /// Turns iCloud sync off on this device, which keeps all it has. With
  /// [deleteFromICloud], NekoSurf's data goes from iCloud too, which turns
  /// it off on other devices; throws [SyncFailed], and stays on, if that
  /// doesn't work.
  Future<void> turnOff({bool deleteFromICloud = false}) async {
    await _invoke('stop', <String, Object>{'delete': deleteFromICloud});
    await _setOff();
    await markAsked(_prefs!);
    notifyListeners();
  }

  /// Deletes NekoSurf's data from iCloud, while sync is off here.
  Future<void> deleteFromICloud() => _invoke('deleteCloud');

  /// What sync did lately, as the Swift side logs it, after how things
  /// stand now: to see why something hasn't reached another device.
  Future<String> log() async => await _invoke('log') as String? ?? '';

  /// Sends what's waiting and fetches what's new, at once, as fetching
  /// needn't wait for saved files to go up; then sends what iCloud doesn't
  /// have. Done when all is, and throws [SyncFailed] as soon as any fails.
  Future<void> syncNow() async {
    await _flush();
    await Future.wait(<Future<Object?>>[
      _invoke('send'),
      _invoke('fetch'),
    ], eagerError: true);
    _filesMayHaveCome.ping();
    await processInbox();
    await _sendWhatICloudLacks();
  }

  bool _checking = false;

  /// Once, after updating to a NekoSurf that does it: what iCloud lost
  /// before then goes up again (see [_sendWhatICloudLacks]).
  Future<void> _checkICloudOnce() async {
    if (_checking) {
      return;
    }
    _checking = true;
    try {
      await _invoke('fetch');
      await processInbox();
      if (await _sendWhatICloudLacks()) {
        await _prefs!.setBool(_checkedKey, true);
      }
    } on SyncFailed catch (e) {
      debugPrint('iCloud sync could not check what iCloud has: $e');
    } finally {
      _checking = false;
    }
  }

  /// Sends what's here that iCloud doesn't have: as when it never went up,
  /// or was lost there, as older saved files were. Only after what changed
  /// elsewhere is applied here, so what was deleted elsewhere is gone here
  /// too, rather than sent back. False if iCloud has no data of NekoSurf's.
  Future<bool> _sendWhatICloudLacks() async {
    if (!isOn || _joining) {
      return false;
    }
    final List<Object?>? ids = await _invoke('cloudIds') as List<Object?>?;
    if (ids == null || !isOn) {
      return false;
    }
    final Set<Object?> there = ids.toSet();
    final List<SyncItem> lacking = <SyncItem>[
      for (final SyncItem item in await snapshot())
        if (!there.contains(item.id)) item,
    ];
    if (lacking.isNotEmpty) {
      putAll(lacking);
      await _flush();
    }
    return true;
  }

  /// The app is left: sends what's waiting while it still can.
  Future<void> flush() async {
    if (!isOn) {
      return;
    }
    await _flush();
    try {
      await _invoke('flush');
    } on SyncFailed {
      // Sent next time.
    }
  }

  /// The app is back: fetches what changed meanwhile, in case a push was
  /// missed.
  Future<void> fetchQuietly() async {
    if (!isOn || _joining) {
      return;
    }
    try {
      await _invoke('fetch');
      _filesMayHaveCome.ping();
    } on SyncFailed {
      // Fetched next time.
    }
  }
}
