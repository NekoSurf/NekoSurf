import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chan/saved/saved_attachment.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android's storage access was refused.
class StorageDenied implements Exception {
  const StorageDenied();
}

/// Where saved files live. Thumbnails stay in the app's private folder, so they
/// never show up in Files or the Download folder.
class SavedFolders {
  const SavedFolders({
    required this.media,
    required this.thumbnails,
    this.elsewhere,
  });

  final String media;
  final String thumbnails;

  /// The folder saved files are kept in with "Keep saved files in the app"
  /// the other way, where one may have been left: written there by a save
  /// or an iCloud download that started before they moved, say. Null if
  /// it can't be looked in (Android without storage access).
  final String? elsewhere;

  String mediaPath(SavedAttachment attachment) =>
      pathOfFile(attachment.fileName);

  String pathOfFile(String fileName) => '$media/$fileName';

  String thumbnailPath(SavedAttachment attachment) => attachment.hasOwnThumbnail
      ? '$thumbnails/${attachment.thumbnail}'
      : mediaPath(attachment);
}

/// The folders for saved files, there when this returns.
///
/// Shown in Files, on iOS that's the app's own Documents folder, which needs
/// no permission. On Android it's Download/4Chan, which needs storage
/// access: throws [StorageDenied] without it. With [ask] false it only checks
/// for that access, without asking for it. Hidden from Files (the setting
/// [savedFilesHiddenKey]), it's a folder of the app's own, on both.
Future<SavedFolders> openSavedFolders({bool ask = true}) async {
  final bool hidden =
      (await SharedPreferences.getInstance()).getBool(savedFilesHiddenKey) ??
      false;
  final Directory support = await getApplicationSupportDirectory();
  final String private = _privateMediaFolder(support);
  final SavedFolders folders = SavedFolders(
    media: hidden ? private : await _shownMediaFolder(ask),
    thumbnails: '${support.path}/savedThumbnails',
    elsewhere: hidden ? await _shownMediaFolderIfAllowed() : private,
  );
  await Directory(folders.thumbnails).create(recursive: true);
  await Directory(folders.media).create(recursive: true);
  return folders;
}

/// Where the saved list is kept: SavedAttachmentsProvider.storageKey.
const String _savedListKey = 'savedAttachments';

String _privateMediaFolder(Directory support) => '${support.path}/savedMedia';

/// Where saved files are when they show in Files (or Download).
Future<String> _shownMediaFolder(bool ask) async => Platform.isAndroid
    ? '${(await _androidBaseFolder(ask: ask)).path}/savedAttachments'
    : (await getApplicationDocumentsDirectory()).path;

/// [_shownMediaFolder], if it can be looked in without asking.
Future<String?> _shownMediaFolderIfAllowed() async {
  try {
    return await _shownMediaFolder(false);
  } on StorageDenied {
    return null;
  }
}

/// Moves [fileName] from [SavedFolders.elsewhere] to where saved files are
/// now, if it's there and not here; whether it did.
Future<bool> bringBackSavedFile(SavedFolders folders, String fileName) async {
  final String? elsewhere = folders.elsewhere;
  if (elsewhere == null) {
    return false;
  }
  final File stray = File('$elsewhere/$fileName');
  final String path = folders.pathOfFile(fileName);
  try {
    if (!await stray.exists() || await File(path).exists()) {
      return false;
    }
    await _move(stray, path);
    return true;
  } on FileSystemException catch (e) {
    debugPrint('Bringing back $fileName failed: $e');
    return false;
  }
}

/// Whether saved files can be moved in or out of Files: on Android, asks for
/// the storage access the Download folder needs.
Future<bool> canMoveSavedFiles() async {
  if (!Platform.isAndroid) {
    return true;
  }
  try {
    await _androidBaseFolder(ask: true);
    return true;
  } on StorageDenied {
    return false;
  }
}

/// Moves the files [prefs] lists as saved into the app's own folder, out of
/// Files (or Android's Download folder), or back with [hidden] false, and
/// keeps that. Throws [StorageDenied] if Android's storage access is needed
/// and refused, having moved nothing.
/// [onProgress] hears how many of how many files are done, as they are.
Future<void> moveSavedFiles(
  SharedPreferences prefs, {
  required bool hidden,
  MoveProgress? onProgress,
}) => _moveSavedFiles(prefs, hidden: hidden, ask: true, onProgress: onProgress);

/// How many of [total] saved files have moved so far.
typedef MoveProgress = void Function(int done, int total);

/// Set while saved files are moved: if it's still there on launch, the app
/// was closed meanwhile.
const String savedFilesMovingKey = 'savedFilesMoving';

/// Finishes moving saved files, if the app was closed while it did;
/// quietly does nothing it can't.
Future<void> finishMovingSavedFiles(SharedPreferences prefs) async {
  final bool? hidden = prefs.getBool(savedFilesMovingKey);
  if (hidden == null) {
    return;
  }
  try {
    await _moveSavedFiles(prefs, hidden: hidden, ask: false);
  } catch (e) {
    debugPrint('Moving saved files failed: $e');
  }
}

Future<void> _moveSavedFiles(
  SharedPreferences prefs, {
  required bool hidden,
  required bool ask,
  MoveProgress? onProgress,
}) async {
  final String private = _privateMediaFolder(
    await getApplicationSupportDirectory(),
  );
  final String shown = await _shownMediaFolder(ask);
  await moveSavedFilesBetween(
    prefs,
    hidden: hidden,
    from: hidden ? shown : private,
    to: hidden ? private : shown,
    onProgress: onProgress,
  );
}

/// Moves the files [prefs] lists as saved [from] one folder [to] the other,
/// and keeps that they're [hidden] from Files, or not.
@visibleForTesting
Future<void> moveSavedFilesBetween(
  SharedPreferences prefs, {
  required bool hidden,
  required String from,
  required String to,
  MoveProgress? onProgress,
}) async {
  await Directory(to).create(recursive: true);
  await prefs.setBool(savedFilesMovingKey, hidden);
  final List<String> fileNames = <String>[
    for (final String entry
        in prefs.getStringList(_savedListKey) ?? const <String>[])
      ?SavedAttachment.fromStored(entry)?.fileName,
  ];
  onProgress?.call(0, fileNames.length);
  for (int i = 0; i < fileNames.length; i++) {
    final File file = File('$from/${fileNames[i]}');
    final String path = '$to/${fileNames[i]}';
    if (await file.exists() && !await File(path).exists()) {
      await _move(file, path);
    }
    onProgress?.call(i + 1, fileNames.length);
  }
  await prefs.setBool(savedFilesHiddenKey, hidden);
  await prefs.remove(savedFilesMovingKey);
}

/// Renames [file] to [path], or, across volumes (Android's Download folder
/// isn't on the app's), copies and deletes it. The copy is made under
/// another name and renamed once it's whole, so a copy cut short (a full
/// phone) never passes for the file; the original goes only after.
Future<void> _move(File file, String path) async {
  try {
    await file.rename(path);
    return;
  } on FileSystemException {
    // Another volume: copied below.
  }
  final File partial = File('$path.moving');
  try {
    await file.copy(partial.path);
    await partial.rename(path);
  } catch (_) {
    try {
      await partial.delete();
    } on FileSystemException {
      // Never made.
    }
    rethrow;
  }
  await file.delete();
}

Future<Directory> _androidBaseFolder({required bool ask}) async {
  final int sdkVersion = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
  final Permission permission = sdkVersion >= 30
      ? Permission.manageExternalStorage
      : Permission.storage;

  final bool granted = ask
      ? await permission.request().isGranted
      : await permission.isGranted;
  if (!granted) {
    throw const StorageDenied();
  }

  final Directory external = (await getExternalStorageDirectory())!;
  String path = '';
  for (final String folder in external.path.split('/').skip(1)) {
    if (folder == 'Android') {
      break;
    }
    path += '/$folder';
  }
  return Directory('$path/Download/4Chan');
}

// Phones' file systems (APFS, ext4) take names of up to 255 bytes; this
// leaves room for " (99)" and the extension.
const int _maxNameBytes = 200;

/// [name] fit to be (the start of) a file name: no path separators or
/// control characters, at most 100 characters and [_maxNameBytes] bytes,
/// without cutting a character in two. 4chan passes on uploaders' names
/// as they were, which can be long, and Japanese takes 3 bytes a character.
String _safeBaseName(String name) {
  final String cleaned = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .trim();
  final StringBuffer out = StringBuffer();
  int bytes = 0;
  int chars = 0;
  for (final int rune in cleaned.runes) {
    final int size = utf8.encode(String.fromCharCode(rune)).length;
    if (chars >= 100 || bytes + size > _maxNameBytes) {
      break;
    }
    out.writeCharCode(rune);
    bytes += size;
    chars += rune > 0xFFFF ? 2 : 1;
  }
  return out.toString().trim();
}

/// The start of a file name that [fileName] gives; null if nothing of it is left.
String? _usableBaseName(String fileName) {
  final String base = _safeBaseName(getNameWithoutExtension(fileName));
  return base.isEmpty || base.startsWith('.') ? null : base;
}

/// What saving or sharing calls the file it downloads [fileName] into (and
/// so Photos or the share sheet shows): the uploader's name made safe
/// ([_safeBaseName]), or "file" if nothing of it is left.
String localFileName(String fileName) {
  final int dot = fileName.lastIndexOf('.');
  final String ext = dot < 0 ? '' : fileName.substring(dot);
  return '${_usableBaseName(fileName) ?? 'file'}$ext';
}

// Names saves have picked but not written yet: two uploads called the same
// thing, saved at once, mustn't both pick "cat.mp4".
final Set<String> _reservedSavedPaths = <String>{};

/// Uploader-facing on-disk name (e.g. "cat.mp4"), unique within [dir] and
/// among names reserved by saves in progress; null if unusable. With
/// [reserve], it's held for this save until [releaseSavedFileName].
Future<String?> uniqueSavedFileName(
  String dir,
  String originalName,
  String ext, {
  bool reserve = false,
}) async {
  final String? clipped = _usableBaseName(originalName);
  if (clipped == null) {
    return null;
  }

  String candidate = '$clipped$ext';
  for (int n = 2; ; n++) {
    final String path = '$dir/$candidate';
    // Checked after the await, with nothing in between to take it.
    if (!await File(path).exists() && !_reservedSavedPaths.contains(path)) {
      if (reserve) {
        _reservedSavedPaths.add(path);
      }
      return candidate;
    }
    candidate = '$clipped ($n)$ext';
  }
}

void releaseSavedFileName(String dir, String name) {
  _reservedSavedPaths.remove('$dir/$name');
}
