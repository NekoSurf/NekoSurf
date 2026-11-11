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

/// What's in the Saved tab, oldest first. Whatever needs the files throws
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
    ];
    if (!listEquals(stored, _encoded())) {
      unawaited(_store());
    }
    saves.addListener(notifyListeners);
    _sync.attach(this);
  }

  /// Where the list is kept in SharedPreferences.
  static const String storageKey = 'savedAttachments';

  final SharedPreferences _prefs;
  final CloudSync _sync;

  /// The folders what comes in from iCloud goes to, without asking for
  /// access (iCloud sync is only on iPhone and iPad, which don't ask).
  final Future<SavedFolders> Function() _syncFolders;
  late List<SavedAttachment> _attachments;
  bool _migrated = false;

  /// Uploads being saved now, by their `tim`. Here rather than in a viewer, so
  /// one reopened meanwhile still shows them saving, and can't save them twice.
  final MediaTasks saves = MediaTasks();

  List<SavedAttachment> get attachments =>
      List<SavedAttachment>.unmodifiable(_attachments);

  /// Whether the upload [id] (its `tim`) is saved.
  bool contains(String id) => _attachments.any((a) => a.id == id);

  List<String> _encoded() => <String>[
    for (final SavedAttachment attachment in _attachments)
      json.encode(attachment),
  ];

  Future<void> _store() => _prefs.setStringList(storageKey, _encoded());

  /// Saves [post]'s upload in a file called [fileName].
  Future<void> save(Post post, {required String fileName}) async {
    final String id = post.uploadId;
    if (contains(id)) {
      return;
    }
    await saves.run(id, (SaveProgress onProgress) async {
      final SavedFolders folders = await openSavedFolders();
      final SavedAttachment attachment = await downloadToSaved(
        folders,
        post,
        diskName: fileName,
        onProgress: onProgress,
      );
      _attachments.add(attachment);
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
  /// file was deleted outside the app. Saves and removals can finish meanwhile.
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
      if (await File(folders.mediaPath(attachment)).exists()) {
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
  /// there.
  @override
  Future<void> applySync(List<SyncChange> changes) async {
    final SavedFolders folders = await _syncFolders();
    bool changed = false;
    for (final SyncChange change in changes) {
      if (change.deleted) {
        final List<SavedAttachment> removed = <SavedAttachment>[
          for (final SavedAttachment a in _attachments)
            if (change.isFor(a.id)) a,
        ];
        _attachments.removeWhere(removed.contains);
        for (final SavedAttachment attachment in removed) {
          changed = true;
          try {
            await _deleteFiles(folders, attachment);
          } on FileSystemException catch (e) {
            debugPrint('$e');
          }
        }
        continue;
      }
      final SavedAttachment? remote = SavedAttachment.fromStored(
        json.encode(change.data),
      );
      final String? media = change.media;
      if (remote == null ||
          contains(remote.id) ||
          media == null ||
          !await File(media).exists()) {
        continue;
      }
      SavedAttachment added = remote;
      if (await File(folders.mediaPath(remote)).exists()) {
        final String name = remote.fileName;
        final String ext = name.contains('.') ? '.${name.split('.').last}' : '';
        final String? free = await uniqueSavedFileName(
          folders.media,
          getNameWithoutExtension(name),
          ext,
        );
        if (free == null) {
          continue;
        }
        added = remote.renamedTo(free);
      }
      await _moveFile(media, folders.mediaPath(added));
      final String? thumbnail = change.thumbnail;
      if (added.hasOwnThumbnail &&
          thumbnail != null &&
          await File(thumbnail).exists() &&
          !await File(folders.thumbnailPath(added)).exists()) {
        await _moveFile(thumbnail, folders.thumbnailPath(added));
      }
      _attachments.add(added);
      changed = true;
    }
    if (changed) {
      notifyListeners();
      await _store();
    }
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
    _sync.detach(this);
    saves.dispose();
    super.dispose();
  }
}
