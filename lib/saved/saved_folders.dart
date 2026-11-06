import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_chan/saved/saved_attachment.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Android's storage access was refused.
class StorageDenied implements Exception {
  const StorageDenied();
}

/// Where saved files live. Thumbnails stay in the app's private folder, so they
/// never show up in Files or the Download folder.
class SavedFolders {
  const SavedFolders({required this.media, required this.thumbnails});

  final String media;
  final String thumbnails;

  String mediaPath(SavedAttachment attachment) =>
      pathOfFile(attachment.fileName);

  String pathOfFile(String fileName) => '$media/$fileName';

  String thumbnailPath(SavedAttachment attachment) => attachment.hasOwnThumbnail
      ? '$thumbnails/${attachment.thumbnail}'
      : mediaPath(attachment);
}

/// The folders for saved files, there when this returns.
///
/// On iOS that's the app's own Documents folder (browsable in Files), which
/// needs no permission. On Android it's Download/4Chan, which needs storage
/// access: throws [StorageDenied] without it. With [ask] false it only checks
/// for that access, without asking for it.
Future<SavedFolders> openSavedFolders({bool ask = true}) async {
  final Directory base = Platform.isAndroid
      ? await _androidBaseFolder(ask: ask)
      : await getApplicationDocumentsDirectory();
  final Directory support = await getApplicationSupportDirectory();
  final SavedFolders folders = SavedFolders(
    media: Platform.isIOS ? base.path : '${base.path}/savedAttachments',
    thumbnails: '${support.path}/savedThumbnails',
  );
  await Directory(folders.thumbnails).create(recursive: true);
  await Directory(folders.media).create(recursive: true);
  return folders;
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
