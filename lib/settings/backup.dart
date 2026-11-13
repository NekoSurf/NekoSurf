import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter_chan/saved/saved_attachment.dart';
import 'package:flutter_chan/saved/saved_attachments_model.dart';
import 'package:flutter_chan/saved/saved_folders.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A backup of what NekoSurf keeps: its preferences (settings, bookmarks,
/// history, hidden posts and filters, the Saved tab's list) and the saved
/// files themselves, so deleting the app doesn't lose them.
///
/// It's a zip ([createBackupFile]) of a folder:
///
///     backup.json   the preferences, and when they were backed up
///     media/        the saved files, under their names in the Saved tab
///     thumbnails/   the thumbnails videos have of their own

const String backupJsonName = 'backup.json';
const String _mediaFolder = 'media';
const String _thumbnailsFolder = 'thumbnails';

// Newer versions may write a newer format, which this one can't read.
const int _format = 1;

/// Preferences about this install rather than what's backed up, like
/// whether it syncs with iCloud: never backed up, nor replaced by a restore.
bool isLocalPreference(String key) =>
    key.startsWith('sync.') ||
    key == savedFilesHiddenKey ||
    key == savedFilesMovingKey;

/// The backup isn't one, or is from a newer NekoSurf.
class NotABackup implements Exception {
  const NotABackup({this.newer = false});

  /// It's from a newer version of NekoSurf.
  final bool newer;

  @override
  String toString() => newer
      ? 'This backup is from a newer NekoSurf: update the app first.'
      : 'This file is not a NekoSurf backup.';
}

/// What's backed up of [prefs]: every preference but this install's own.
Map<String, Object> backedUpPreferences(SharedPreferences prefs) => {
  for (final String key in prefs.getKeys())
    if (!isLocalPreference(key) && prefs.get(key) != null) key: prefs.get(key)!,
};

List<SavedAttachment> _savedIn(Object? stored) => <SavedAttachment>[
  if (stored is List)
    for (final Object? entry in stored)
      if (entry is String) ?SavedAttachment.fromStored(entry),
];

String _backupJson(Map<String, Object> preferences, DateTime madeAt) =>
    jsonEncode(<String, Object>{
      'format': _format,
      'madeAt': madeAt.toUtc().toIso8601String(),
      'preferences': preferences,
    });

/// The backup.json in [dir] read; throws [NotABackup] if it isn't one.
Future<Map<String, dynamic>> _readBackupJson(Directory dir) async {
  final File file = File('${dir.path}/$backupJsonName');
  if (!await file.exists()) {
    throw const NotABackup();
  }
  final Map<String, dynamic> backup;
  try {
    backup = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  } catch (_) {
    throw const NotABackup();
  }
  final Object? format = backup['format'];
  if (format is! int || backup['preferences'] is! Map) {
    throw const NotABackup();
  }
  if (format > _format) {
    throw const NotABackup(newer: true);
  }
  return backup;
}

/// What's backed up: [prefs] but this install's own, with the Saved list
/// down to the files that are in [folders]; and those files, each with its
/// path in the backup. So a backup only lists files it has.
Future<(Map<String, Object>, List<(File, String)>)> _snapshot(
  SharedPreferences prefs,
  SavedFolders folders,
) async {
  final Map<String, Object> preferences = backedUpPreferences(prefs);
  final Object? stored = preferences[SavedAttachmentsProvider.storageKey];
  final List<String> saved = <String>[];
  final List<(File, String)> files = <(File, String)>[];
  for (final SavedAttachment attachment in _savedIn(stored)) {
    final File media = File(folders.mediaPath(attachment));
    if (!await media.exists()) {
      continue;
    }
    saved.add(jsonEncode(attachment));
    files.add((media, '$_mediaFolder/${attachment.fileName}'));
    if (attachment.hasOwnThumbnail) {
      final File thumbnail = File(folders.thumbnailPath(attachment));
      if (await thumbnail.exists()) {
        files.add((thumbnail, '$_thumbnailsFolder/${attachment.thumbnail}'));
      }
    }
  }
  if (stored != null) {
    preferences[SavedAttachmentsProvider.storageKey] = saved;
  }
  return (preferences, files);
}

/// A zip of a backup of [prefs] and [folders] in [into], named after the
/// day: a file to keep anywhere and restore with [restoreBackupFile].
Future<File> createBackupFile(
  SharedPreferences prefs,
  SavedFolders folders,
  Directory into, {
  DateTime? now,
}) async {
  final DateTime madeAt = now ?? DateTime.now();
  final (Map<String, Object> preferences, List<(File, String)> sources) =
      await _snapshot(prefs, folders);
  // Paths alone go to the isolate.
  final List<(String, String)> files = <(String, String)>[
    for (final (File source, String path) in sources) (source.path, path),
  ];

  String two(int n) => n.toString().padLeft(2, '0');
  final String day = '${madeAt.year}-${two(madeAt.month)}-${two(madeAt.day)}';
  final String zipPath = '${into.path}/NekoSurf Backup $day.zip';
  final String json = _backupJson(preferences, madeAt);
  // Hundreds of MB of videos: not on the UI thread.
  await Isolate.run(() async {
    // Stored, not compressed: videos and images already are.
    final ZipFileEncoder encoder = ZipFileEncoder()
      ..create(zipPath, level: ZipFileEncoder.store);
    encoder.addArchiveFile(ArchiveFile.string(backupJsonName, json));
    for (final (String source, String path) in files) {
      await encoder.addFile(File(source), path);
    }
    await encoder.close();
  });
  return File(zipPath);
}

/// Restores the backup zipped at [path] (see [createBackupFile]) with
/// [restoreBackupFolder], unpacking it in [scratch] first.
Future<void> restoreBackupFile(
  String path,
  SharedPreferences prefs,
  SavedFolders folders,
  Directory scratch,
) async {
  final Directory unpacked = await scratch.createTemp('restore');
  try {
    try {
      await Isolate.run(() => extractFileToDisk(path, unpacked.path));
    } catch (_) {
      throw const NotABackup();
    }
    await restoreBackupFolder(unpacked, prefs, folders);
  } finally {
    try {
      await unpacked.delete(recursive: true);
    } catch (_) {}
  }
}

/// Restores the backup in [dir]: its preferences replace [prefs] (all but
/// this install's own), and its saved files are added to what's saved now
/// in [folders]. One whose name is taken here is renamed; one that's saved
/// here already stays as it is. Throws [NotABackup] before changing
/// anything if [dir] doesn't hold one.
///
/// What the app has loaded must be built again from [prefs] afterwards.
Future<void> restoreBackupFolder(
  Directory dir,
  SharedPreferences prefs,
  SavedFolders folders,
) async {
  final Map<String, dynamic> backup = await _readBackupJson(dir);
  final Map<String, Object> preferences = <String, Object>{
    for (final MapEntry<dynamic, dynamic> entry
        in (backup['preferences'] as Map).entries)
      if (entry.key is String && entry.value != null)
        entry.key as String: entry.value as Object,
  };

  final List<SavedAttachment> current = _savedIn(
    prefs.getStringList(SavedAttachmentsProvider.storageKey),
  );
  final Set<String> currentIds = <String>{
    for (final SavedAttachment attachment in current) attachment.id,
  };
  final List<SavedAttachment> restored = <SavedAttachment>[];
  for (final SavedAttachment attachment in _savedIn(
    preferences[SavedAttachmentsProvider.storageKey],
  )) {
    final File media = File('${dir.path}/$_mediaFolder/${attachment.fileName}');
    if (currentIds.contains(attachment.id) || !await media.exists()) {
      continue;
    }
    SavedAttachment added = attachment;
    if (await File(folders.mediaPath(attachment)).exists()) {
      final String name = attachment.fileName;
      final String ext = name.contains('.') ? '.${name.split('.').last}' : '';
      final String? free = await uniqueSavedFileName(
        folders.media,
        getNameWithoutExtension(name),
        ext,
      );
      if (free == null) {
        continue;
      }
      added = attachment.renamedTo(free);
    }
    await media.copy(folders.mediaPath(added));
    if (added.hasOwnThumbnail) {
      final File thumbnail = File(
        '${dir.path}/$_thumbnailsFolder/${attachment.thumbnail}',
      );
      final File target = File(folders.thumbnailPath(added));
      if (await thumbnail.exists() && !await target.exists()) {
        await thumbnail.copy(target.path);
      }
    }
    restored.add(added);
    currentIds.add(added.id);
  }

  // Last: until here, nothing the app reads has changed.
  for (final String key in prefs.getKeys().toList()) {
    if (!isLocalPreference(key)) {
      await prefs.remove(key);
    }
  }
  for (final MapEntry<String, Object> entry in preferences.entries) {
    if (!isLocalPreference(entry.key)) {
      await _setPreference(prefs, entry.key, entry.value);
    }
  }
  // The backup's saved files (older) first, then what's saved here.
  await prefs.setStringList(SavedAttachmentsProvider.storageKey, <String>[
    for (final SavedAttachment attachment in <SavedAttachment>[
      ...restored,
      ...current,
    ])
      jsonEncode(attachment),
  ]);
}

Future<void> _setPreference(
  SharedPreferences prefs,
  String key,
  Object value,
) async {
  switch (value) {
    case bool():
      await prefs.setBool(key, value);
    case int():
      await prefs.setInt(key, value);
    case double():
      await prefs.setDouble(key, value);
    case String():
      await prefs.setString(key, value);
    case List():
      await prefs.setStringList(key, <String>[
        for (final Object? item in value)
          if (item is String) item,
      ]);
  }
}
