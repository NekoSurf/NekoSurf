import 'package:flutter/services.dart';
import 'package:flutter_chan/settings/settings_model.dart';

/// Where Save to Photos puts a file on Android: in the folder picked in
/// Settings (any folder Android's picker offers), or by default in Pictures
/// or Movies, as the gallery does; and, saved from a thread with "A folder
/// per thread" on, in a folder for that thread inside it. iPhone saves to
/// the Photos library, which has no folders, so it ignores both.
class PhotosPlace {
  const PhotosPlace({this.folder, this.subfolder});

  /// Where [settings] say saves go, and in [threadFolder] if they keep a
  /// folder per thread.
  factory PhotosPlace.of(SettingsProvider settings, {String? threadFolder}) {
    final String folder = settings.downloadFolder.value;
    return PhotosPlace(
      folder: folder.isEmpty ? null : folder,
      subfolder: settings.folderPerThread.value ? threadFolder : null,
    );
  }

  /// The picked folder, as Android's picker named it; null for the default.
  final String? folder;

  /// A folder inside it, made if it isn't there.
  final String? subfolder;
}

/// The picked download folder can't be written to any more: it's gone, its
/// SD card was taken out, or the app's access to it was taken back.
class DownloadFolderGone implements Exception {
  const DownloadFolderGone();
}

const MethodChannel _channel = MethodChannel('nekosurf/download_folder');

/// Lets the person pick a folder with Android's folder picker; null if they
/// backed out. The app keeps access to it until [forgetDownloadFolder].
Future<String?> pickDownloadFolder() => _channel.invokeMethod<String>('pick');

/// Gives up the access [pickDownloadFolder] got to [folder].
Future<void> forgetDownloadFolder(String folder) =>
    _channel.invokeMethod<void>('forget', <String, String>{'folder': folder});

/// Copies the file at [path] into [folder] (in its [subfolder], if given)
/// as [name], numbered by Android if that's taken. Throws
/// [DownloadFolderGone], or if it doesn't get there.
Future<void> copyToDownloadFolder(
  String folder,
  String path,
  String name, {
  String? subfolder,
}) async {
  try {
    await _channel.invokeMethod<void>('copy', <String, String?>{
      'folder': folder,
      'subfolder': subfolder,
      'path': path,
      'name': name,
    });
  } on PlatformException catch (e) {
    if (e.code == 'gone') {
      throw const DownloadFolderGone();
    }
    rethrow;
  }
}

/// How the picked [folder] is shown in Settings: its path in the phone's
/// storage, like "Download/NekoSurf", or on an SD card, "SD card/Pictures".
String downloadFolderLabel(String folder) {
  final String path = Uri.parse(folder).pathSegments.lastOrNull ?? '';
  final int colon = path.indexOf(':');
  if (colon < 0) {
    return path.isEmpty ? folder : path;
  }
  final String volume = path.substring(0, colon);
  final String inside = path.substring(colon + 1);
  final String root = volume == 'primary' ? 'Phone storage' : 'SD card';
  return inside.isEmpty
      ? root
      : volume == 'primary'
      ? inside
      : '$root/$inside';
}

/// The longest a thread's folder name gets, before it's cut.
const int _threadFolderLength = 80;

/// The folder for thread [number] with [title] (its subject, or the start
/// of its first post), like "123456 - Subject": without the characters
/// file names can't have, and cut short if it's long.
String threadFolderName(int number, String? title) {
  String text = (title ?? '')
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f\x7f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final String start = '$number - ';
  if (text.length > _threadFolderLength - start.length) {
    text = text.substring(0, _threadFolderLength - start.length);
  }
  // Nor can they end in a dot or a space.
  text = text.replaceAll(RegExp(r'[. ]+$'), '');
  return text.isEmpty ? '$number' : '$start$text';
}
