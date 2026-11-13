import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/saved/downloads.dart';
import 'package:flutter_chan/saved/media_tasks.dart';
import 'package:flutter_chan/saved/saved_attachment.dart';
import 'package:flutter_chan/saved/saved_folders.dart';
import 'package:flutter_chan/saved/saved_migrations.dart';
import 'package:flutter_chan/sync/cloud_sync.dart';
import 'package:flutter_chan/sync/sync_items.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [attachment], as iCloud sync keeps it, with its file in [folders].
SyncItem savedSyncItem(SavedAttachment attachment, SavedFolders folders) =>
    SyncItem(
      SyncKind.saved,
      attachment.id,
      attachment.withStoredId().toJson(),
      media: folders.mediaPath(attachment),
      thumbnail: attachment.hasOwnThumbnail
          ? folders.thumbnailPath(attachment)
          : null,
    );

/// Which of two goes first in the Saved tab: the same on every device.
int _bySortTime(SavedAttachment a, SavedAttachment b) {
  final int byTime = a.sortTime.compareTo(b.sortTime);
  if (byTime != 0) {
    return byTime;
  }
  final int byId = a.id.compareTo(b.id);
  return byId != 0 ? byId : a.fileName.compareTo(b.fileName);
}

/// What's in the Saved tab, oldest first, by when each was saved (see
/// [SavedAttachment.sortTime]). With iCloud sync on, what was saved on
/// another device shows up at once, its thumbnail with it: a placeholder
/// till its file comes down. Whatever needs the files throws
/// [StorageDenied] without access to them, and changes nothing.
class SavedAttachmentsProvider with ChangeNotifier implements SyncTarget {
  SavedAttachmentsProvider(
    this._prefs, {
    CloudSync? sync,
    Future<SavedFolders> Function()? syncFolders,
  }) : _sync = sync ?? CloudSync.instance,
       _syncFolders = syncFolders ?? (() => openSavedFolders(ask: false)) {
    final List<String> stored =
        _prefs.getStringList(storageKey) ?? const <String>[];
    _attachments = <SavedAttachment>[
      for (final String entry in stored) ?SavedAttachment.fromStored(entry),
    ]..sort(_bySortTime);
    _loadPlaceholders();
    if (!listEquals(stored, _encoded())) {
      unawaited(_store());
    }
    saves.addListener(notifyListeners);
    _sync.attach(this);
    _sync.filesMayHaveCome.addListener(_downloadWaiting);
    _downloadWaiting();
  }

  /// Where the list is kept in SharedPreferences.
  static const String storageKey = 'savedAttachments';

  /// Which of them are placeholders, whose files are still in iCloud, with
  /// how big each is there (null: still going up from where it was
  /// saved). This device's own, so not backed up (see isLocalPreference).
  static const String placeholdersKey = 'sync.savedPlaceholders';

  final SharedPreferences _prefs;
  final CloudSync _sync;

  /// The folders what comes in from iCloud goes to, without asking for
  /// access (iCloud sync is only on iPhone and iPad, which don't ask).
  final Future<SavedFolders> Function() _syncFolders;
  late List<SavedAttachment> _attachments;
  final Map<String, int?> _placeholders = <String, int?>{};
  bool _migrated = false;

  /// Uploads being saved now, by their `tim`. Here rather than in a viewer, so
  /// one reopened meanwhile still shows them saving, and can't save them twice.
  final MediaTasks saves = MediaTasks();

  List<SavedAttachment> get attachments =>
      List<SavedAttachment>.unmodifiable(_attachments);

  /// Whether the upload [id] (its `tim`) is saved, here or still coming
  /// from iCloud.
  bool contains(String id) => _attachments.any((a) => a.id == id);

  /// Whether [attachment]'s file is here, rather than still in iCloud.
  bool hasFile(SavedAttachment attachment) =>
      !_placeholders.containsKey(attachment.id);

  /// Whether [attachment]'s file, still in iCloud, is there to download
  /// yet; false while it's going up from the device it was saved on.
  bool isInICloud(SavedAttachment attachment) =>
      _placeholders[attachment.id] != null;

  /// Of the files called [fileNames], those that are here.
  Set<String> filesHere(Iterable<String> fileNames) => <String>{
    for (final SavedAttachment a in _attachments)
      if (hasFile(a) && fileNames.contains(a.fileName)) a.fileName,
  };

  void _loadPlaceholders() {
    try {
      final Object? decoded = json.decode(
        _prefs.getString(placeholdersKey) ?? '{}',
      );
      if (decoded is Map<String, Object?>) {
        for (final MapEntry<String, Object?> entry in decoded.entries) {
          if (contains(entry.key)) {
            _placeholders[entry.key] = (entry.value as num?)?.toInt();
          }
        }
      }
    } on FormatException {
      // None, then.
    }
    if (!_sync.isOn && _placeholders.isNotEmpty) {
      // They'd never come down: they come back if sync is turned on again.
      _attachments.removeWhere((a) => _placeholders.containsKey(a.id));
      _placeholders.clear();
      unawaited(_storePlaceholders());
    }
  }

  Future<void> _storePlaceholders() =>
      _prefs.setString(placeholdersKey, json.encode(_placeholders));

  /// Asks iCloud for the placeholders' files: those that are there come
  /// down, even ones whose records say they're still going up.
  void _downloadWaiting() =>
      unawaited(_sync.downloadFiles(_placeholders.keys.toList()));

  void _insert(SavedAttachment attachment) {
    final int at = _attachments.indexWhere(
      (SavedAttachment other) => _bySortTime(attachment, other) < 0,
    );
    if (at < 0) {
      _attachments.add(attachment);
    } else {
      _attachments.insert(at, attachment);
    }
  }

  List<String> _encoded() => <String>[
    for (final SavedAttachment attachment in _attachments)
      json.encode(attachment),
  ];

  Future<void> _store() => _prefs.setStringList(storageKey, _encoded());

  int _foldersMoved = 0;

  /// Goes up each time saved files move to another folder ([moveFiles]):
  /// whatever keeps their folders opens them again.
  int get foldersMoved => _foldersMoved;

  /// While saved files move ([moveFiles]): how many of how many are done.
  final ValueNotifier<(int, int)?> moving = ValueNotifier<(int, int)?>(null);

  /// Moves saved files out of Files (or Android's Download folder), or back
  /// with [hidden] false. Throws [StorageDenied] without access to them.
  Future<void> moveFiles({required bool hidden}) async {
    moving.value = (0, 0);
    try {
      await moveSavedFiles(
        _prefs,
        hidden: hidden,
        onProgress: (int done, int total) => moving.value = (done, total),
      );
    } finally {
      moving.value = null;
      _foldersMoved++;
      notifyListeners();
    }
  }

  /// Saves [post]'s upload in a file called [fileName].
  Future<void> save(Post post, {required String fileName}) async {
    final String id = post.uploadId;
    if (contains(id)) {
      return;
    }
    await saves.run(id, (SaveProgress onProgress) async {
      final SavedFolders folders = await openSavedFolders();
      final SavedAttachment attachment = (await downloadToSaved(
        folders,
        post,
        diskName: fileName,
        onProgress: onProgress,
      )).addedAtTime(DateTime.now());
      _insert(attachment);
      _sync.put(savedSyncItem(attachment, folders));
      await _store();
    });
  }

  Future<void> remove(String id) => _removeWhere((a) => a.id == id);

  Future<void> removeFiles(Set<String> fileNames) =>
      _removeWhere((a) => fileNames.contains(a.fileName));

  Future<void> clear() => _removeWhere((_) => true);

  Future<void> _removeWhere(bool Function(SavedAttachment) test) async {
    final SavedFolders folders = await openSavedFolders();
    final List<SavedAttachment> removed = _attachments.where(test).toList();
    _attachments.removeWhere(test);
    _sync.removeAll(SyncKind.saved, [for (final a in removed) a.id]);
    final int placeholders = _placeholders.length;
    for (final SavedAttachment attachment in removed) {
      _placeholders.remove(attachment.id);
    }
    if (_placeholders.length != placeholders) {
      unawaited(_storePlaceholders());
    }
    notifyListeners();
    unawaited(_store());

    for (final SavedAttachment attachment in removed) {
      try {
        await _deleteFiles(folders, attachment);
      } on FileSystemException catch (e) {
        debugPrint('$e');
      }
    }
  }

  Future<void> _deleteFiles(
    SavedFolders folders,
    SavedAttachment attachment,
  ) async {
    for (final String path in <String>{
      folders.mediaPath(attachment),
      folders.thumbnailPath(attachment),
    }) {
      final File file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  /// Brings what older versions left up to date, once, and drops entries whose
  /// file was deleted outside the app: not in [folders], nor left in the
  /// folder they were moved out of ([SavedFolders.elsewhere]), from where
  /// it's brought back. Saves and removals can finish meanwhile.
  Future<void> reconcileWithDisk(SavedFolders folders) async {
    if (!_migrated) {
      _migrated = true;
      final List<SavedAttachment> before = List.of(_attachments);
      final List<SavedAttachment> migrated = await migrateSavedFiles(
        folders,
        before,
      );
      final Map<SavedAttachment, SavedAttachment> changes =
          Map<SavedAttachment, SavedAttachment>.identity();
      for (int index = 0; index < before.length; index++) {
        changes[before[index]] = migrated[index];
      }
      _attachments = <SavedAttachment>[
        for (final SavedAttachment attachment in _attachments)
          changes[attachment] ?? attachment,
      ];
      notifyListeners();
      await _store();
    }

    final List<SavedAttachment> gone = <SavedAttachment>[];
    for (final SavedAttachment attachment in List.of(_attachments)) {
      // A placeholder's file isn't here yet.
      if (!hasFile(attachment) ||
          await File(folders.mediaPath(attachment)).exists() ||
          // Left in the folder they were in before "Keep saved files in
          // the app" moved them: not gone.
          await bringBackSavedFile(folders, attachment.fileName)) {
        continue;
      }
      gone.add(attachment);
      if (attachment.hasOwnThumbnail) {
        final File thumbnail = File(folders.thumbnailPath(attachment));
        if (await thumbnail.exists()) {
          await thumbnail.delete();
        }
      }
    }

    if (gone.isNotEmpty) {
      _attachments.removeWhere(gone.contains);
      _sync.removeAll(SyncKind.saved, [for (final a in gone) a.id]);
      notifyListeners();
      await _store();
    }
  }

  @override
  Set<SyncKind> get syncKinds => const <SyncKind>{SyncKind.saved};

  /// Adds what was saved on another device, its file moved in from iCloud
  /// (renamed if its name is taken here), and removes what was removed
  /// there. What comes without its file is a placeholder, with its
  /// thumbnail, till the file's downloaded.
  @override
  Future<void> applySync(List<SyncChange> changes) async {
    final SavedFolders folders = await _syncFolders();
    bool changed = false;
    final Set<String> toDownload = <String>{};
    for (final SyncChange change in changes) {
      if (change.deleted) {
        final List<SavedAttachment> removed = <SavedAttachment>[
          for (final SavedAttachment a in _attachments)
            if (change.isFor(a.id)) a,
        ];
        _attachments.removeWhere(removed.contains);
        for (final SavedAttachment attachment in removed) {
          changed = true;
          _placeholders.remove(attachment.id);
          try {
            await _deleteFiles(folders, attachment);
          } on FileSystemException catch (e) {
            debugPrint('$e');
          }
        }
        continue;
      }
      final SavedAttachment? existing = _attachments
          .where((a) => change.isFor(a.id))
          .firstOrNull;
      if (change.fileOnly) {
        if (existing != null && !hasFile(existing)) {
          changed |= await _fileCame(folders, existing, change.media);
        }
        continue;
      }
      final SavedAttachment? remote = SavedAttachment.fromStored(
        json.encode(change.data),
      );
      if (remote == null) {
        continue;
      }
      if (existing != null) {
        // When it was saved: the same on every device, for the same order.
        final SavedAttachment current = _withAddedAtOf(existing, remote);
        if (!identical(current, existing)) {
          changed = true;
        }
        if (hasFile(current)) {
          continue;
        }
        if (change.media != null) {
          // Saved by an older NekoSurf, with its file in the record.
          changed |= await _fileCame(folders, current, change.media);
        } else if (_placeholders[current.id] != change.fileBytes) {
          _placeholders[current.id] = change.fileBytes;
          changed = true;
          toDownload.add(current.id);
        }
        continue;
      }
      final String? media = change.media;
      if (media != null && !await File(media).exists()) {
        continue;
      }
      final SavedAttachment? added = await _withFreeName(folders, remote);
      if (added == null) {
        continue;
      }
      final String? thumbnail = change.thumbnail;
      if (added.hasOwnThumbnail &&
          thumbnail != null &&
          await File(thumbnail).exists() &&
          !await File(folders.thumbnailPath(added)).exists()) {
        await _moveFile(thumbnail, folders.thumbnailPath(added));
      }
      if (media != null) {
        await _moveFile(media, folders.mediaPath(added));
      } else {
        _placeholders[added.id] = change.fileBytes;
        toDownload.add(added.id);
      }
      _insert(added);
      changed = true;
    }
    if (changed) {
      notifyListeners();
      await _store();
      await _storePlaceholders();
    }
    unawaited(_sync.downloadFiles(toDownload));
  }

  /// [existing], with when [remote] says it was saved, moved to where that
  /// puts it; [existing] itself if that's the same. iCloud's goes, even
  /// when it has none (saved before that was kept): keeping this one's
  /// then would list it elsewhere than devices that don't have one.
  SavedAttachment _withAddedAtOf(
    SavedAttachment existing,
    SavedAttachment remote,
  ) {
    if (remote.addedAt == existing.addedAt) {
      return existing;
    }
    final SavedAttachment updated = existing.withAddedAt(remote.addedAt);
    _attachments.remove(existing);
    _insert(updated);
    return updated;
  }

  /// [attachment] under a name that isn't taken here, by a file or by
  /// another one still coming; null if there's none.
  Future<SavedAttachment?> _withFreeName(
    SavedFolders folders,
    SavedAttachment attachment,
  ) async {
    bool taken(String name) => _attachments.any(
      (other) => other.fileName == name && other.id != attachment.id,
    );
    String name = attachment.fileName;
    final String ext = name.contains('.') ? '.${name.split('.').last}' : '';
    final String base = getNameWithoutExtension(name);
    for (
      int n = 2;
      taken(name) || await File(folders.pathOfFile(name)).exists();
      n++
    ) {
      final String? free = await uniqueSavedFileName(
        folders.media,
        n == 2 ? base : '$base ($n)',
        ext,
      );
      if (free == null || n > 50) {
        return null;
      }
      name = free;
    }
    return name == attachment.fileName
        ? attachment
        : attachment.renamedTo(name);
  }

  /// The file of the placeholder [attachment] came down, to [media]: it's
  /// moved in, under another name if its own was taken meanwhile.
  Future<bool> _fileCame(
    SavedFolders folders,
    SavedAttachment attachment,
    String? media,
  ) async {
    if (media == null || !await File(media).exists()) {
      return false;
    }
    SavedAttachment done = attachment;
    if (await File(folders.mediaPath(attachment)).exists()) {
      final SavedAttachment? renamed = await _withFreeName(folders, attachment);
      if (renamed == null) {
        return false;
      }
      done = renamed;
      if (attachment.hasOwnThumbnail) {
        final File thumbnail = File(folders.thumbnailPath(attachment));
        if (await thumbnail.exists() &&
            !await File(folders.thumbnailPath(done)).exists()) {
          await _moveFile(thumbnail.path, folders.thumbnailPath(done));
        }
      }
      _attachments[_attachments.indexOf(attachment)] = done;
    }
    await _moveFile(media, folders.mediaPath(done));
    _placeholders.remove(attachment.id);
    return true;
  }

  static Future<void> _moveFile(String from, String to) async {
    try {
      await File(from).rename(to);
    } on FileSystemException {
      await File(from).copy(to);
      await File(from).delete();
    }
  }

  @override
  void dispose() {
    _sync.filesMayHaveCome.removeListener(_downloadWaiting);
    _sync.detach(this);
    saves.dispose();
    moving.dispose();
    super.dispose();
  }
}
