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
import 'package:shared_preferences/shared_preferences.dart';

/// What's in the Saved tab, oldest first. Whatever needs the files throws
/// [StorageDenied] without access to them, and changes nothing.
class SavedAttachmentsProvider with ChangeNotifier {
  SavedAttachmentsProvider(this._prefs) {
    final List<String> stored = _prefs.getStringList(_key) ?? const <String>[];
    _attachments = <SavedAttachment>[
      for (final String entry in stored) ?SavedAttachment.fromStored(entry),
    ];
    if (!listEquals(stored, _encoded())) {
      unawaited(_store());
    }
    saves.addListener(notifyListeners);
  }

  static const String _key = 'savedAttachments';

  final SharedPreferences _prefs;
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

  Future<void> _store() => _prefs.setStringList(_key, _encoded());

  /// Saves [post]'s upload in a file called [fileName].
  Future<void> save(Post post, {required String fileName}) async {
    final String id = post.uploadId;
    if (contains(id)) {
      return;
    }
    await saves.run(id, (SaveProgress onProgress) async {
      final SavedAttachment attachment = await downloadToSaved(
        await openSavedFolders(),
        post,
        diskName: fileName,
        onProgress: onProgress,
      );
      _attachments.add(attachment);
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
      notifyListeners();
      await _store();
    }
  }

  @override
  void dispose() {
    saves.dispose();
    super.dispose();
  }
}
