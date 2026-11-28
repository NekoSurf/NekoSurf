import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_chan/saved/download_folder.dart';
import 'package:flutter_chan/saved/downloads.dart';
import 'package:flutter_chan/saved/saved_folders.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';

/// Access to Photos or the gallery was refused.
class PhotosDenied implements Exception {
  const PhotosDenied();
}

/// Asks to add to Photos or the gallery, unless saves go to a picked
/// folder; it never needs to read them.
Future<void> _askForPhotos(PhotosPlace place) async {
  if (_toPickedFolder(place)) {
    return;
  }
  final bool granted;
  if (Platform.isAndroid) {
    final int sdkVersion =
        (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    granted = sdkVersion >= 29 || await Permission.storage.request().isGranted;
  } else {
    granted = await Permission.photosAddOnly.request().isGranted;
  }
  if (!granted) {
    throw const PhotosDenied();
  }
}

bool _toPickedFolder(PhotosPlace place) =>
    Platform.isAndroid && place.folder != null;

/// Adds the file to Photos, or on Android to [place]; throws
/// [DownloadFolderGone]. saver_gallery never answers on iOS for videos
/// Photos rejects, so cap the wait.
Future<bool> _addToPhotos(String path, String name, PhotosPlace place) async {
  if (_toPickedFolder(place)) {
    try {
      await copyToDownloadFolder(
        place.folder!,
        path,
        name,
        subfolder: place.subfolder,
      );
      return true;
    } on DownloadFolderGone {
      rethrow;
    } catch (e) {
      debugPrint('Download folder save failed for $name: $e');
      return false;
    }
  }
  try {
    final result = await SaverGallery.saveFile(
      filePath: path,
      fileName: name,
      // In Pictures or Movies, as by default, on Android.
      albumPath: Platform.isAndroid ? place.subfolder : null,
      skipIfExists: false,
    ).timeout(const Duration(seconds: 20));
    if (!result.isSuccess) {
      debugPrint('Gallery save failed for $name: ${result.errorMessage}');
    }
    return result.isSuccess;
  } catch (e) {
    debugPrint('Gallery save failed for $name: $e');
    return false;
  }
}

/// Downloads an upload to Photos/gallery, on Android to [place]; throws
/// [PhotosDenied], [DownloadFolderGone], or if it doesn't get there.
Future<void> downloadToPhotos(
  String url,
  String fileName, {
  PhotosPlace place = const PhotosPlace(),
  SaveProgress? onProgress,
}) async {
  await _askForPhotos(place);

  Directory? work;
  try {
    work = await newWorkFolder();
    final File file = await downloadToGive(work, url, fileName, onProgress);
    if (!await _addToPhotos(file.path, file.path.split('/').last, place)) {
      throw Exception('gallery save failed');
    }
  } finally {
    if (work != null) {
      await deleteQuietly(work);
    }
  }
}

/// Copies saved files to Photos/gallery, on Android to [place]; returns how
/// many failed. Throws [PhotosDenied], [DownloadFolderGone] or
/// [StorageDenied].
Future<int> copySavedToPhotos(
  List<String> fileNames, {
  PhotosPlace place = const PhotosPlace(),
}) async {
  await _askForPhotos(place);
  final SavedFolders folders = await openSavedFolders();

  int failed = 0;
  for (final String fileName in fileNames) {
    final String path = folders.pathOfFile(fileName);
    if (!await File(path).exists() ||
        !await _addToPhotos(path, fileName, place)) {
      failed++;
    }
  }
  return failed;
}

/// Opens one share sheet for all given saved files (includes "Save to Files"),
/// pointing [from] the button that asked. Throws [StorageDenied], or if none
/// of them are there any more.
Future<void> shareSaved(
  List<String> fileNames, {
  required ShareAnchor from,
}) async {
  final SavedFolders folders = await openSavedFolders();

  final List<XFile> files = <XFile>[
    for (final String fileName in fileNames)
      if (await File(folders.pathOfFile(fileName)).exists())
        XFile(folders.pathOfFile(fileName)),
  ];
  if (files.isEmpty) {
    throw const FileSystemException('Saved files are gone');
  }
  await shareInTurn(
    from,
    (Rect origin) => ShareParams(files: files, sharePositionOrigin: origin),
  );
}

/// Downloads an upload and opens the share sheet for it, pointing [from] the
/// button that asked.
Future<void> shareDownload(
  String url,
  String fileName, {
  required ShareAnchor from,
  SaveProgress? onProgress,
}) async {
  Directory? shareFolder;
  bool shared = false;
  try {
    shareFolder = await _newShareFolder();
    final File file = await downloadToGive(
      shareFolder,
      url,
      fileName,
      onProgress,
    );
    await shareInTurn(
      from,
      (Rect origin) =>
          ShareParams(files: [XFile(file.path)], sharePositionOrigin: origin),
    );
    shared = true;
  } finally {
    if (shareFolder != null) {
      // What was shared stays until the next share; a failed one goes now.
      finishShareFolder(shareFolder);
      if (!shared) {
        await deleteQuietly(shareFolder);
      }
    }
  }
}

/// How the share sheet is shown; replaced in tests.
@visibleForTesting
Future<void> Function(ShareParams params) showShareSheet =
    (ShareParams params) async {
      await SharePlus.instance.share(params);
    };

/// Opens the share sheet for [file] of [mimeType], once it's free, pointing
/// [from] the button that asked; done when it's closed, by when what it was
/// shared to has its own copy.
Future<void> shareFile(
  File file, {
  required ShareAnchor from,
  String? mimeType,
}) => shareInTurn(
  from,
  (Rect origin) => ShareParams(
    files: [XFile(file.path, mimeType: mimeType)],
    sharePositionOrigin: origin,
  ),
);

/// Opens the share sheet for a link, pointing [from] the button that asked.
Future<void> shareLink(Uri uri, {required ShareAnchor from}) => shareInTurn(
  from,
  (Rect origin) => ShareParams(uri: uri, sharePositionOrigin: origin),
);

/// The button a share sheet points from. On iPad the sheet opens as a
/// popover, which iPad refuses to open without a place inside the window to
/// point at; iPhone ignores it.
///
/// It's looked up when the sheet opens, not when the button is pressed: a
/// share can wait for a download or for another share first, by when the
/// button may have moved, or be gone, as when the viewer it was in has
/// closed.
class ShareAnchor {
  /// Made when [button] is pressed, from the button's own context.
  const ShareAnchor(this._button);

  final BuildContext _button;

  /// The button's box in the window, or the middle of the window when it's
  /// gone or off screen.
  Rect get origin => shareOrigin(_button.mounted ? _button : null);
}

/// See [ShareAnchor.origin].
@visibleForTesting
Rect shareOrigin(BuildContext? from) {
  final ui.FlutterView? view =
      WidgetsBinding.instance.platformDispatcher.implicitView;
  final Rect window = view == null
      ? Rect.largest
      : Offset.zero & (view.physicalSize / view.devicePixelRatio);
  final RenderObject? box = from?.findRenderObject();
  if (box is RenderBox && box.attached && box.hasSize) {
    final Rect shown = (box.localToGlobal(Offset.zero) & box.size).intersect(
      window,
    );
    if (shown.width > 0 && shown.height > 0) {
      return shown;
    }
  }
  return Rect.fromCenter(center: window.center, width: 1, height: 1);
}

// Done when the share sheet is free: it shows one share at a time.
Future<void> _shareSheetFree = Future<void>.value();

/// Opens the share sheet for [params], made for where it points [from] (see
/// [ShareAnchor]), once the shares before it have closed theirs, so shares
/// readied at once open one after another.
@visibleForTesting
Future<void> shareInTurn(
  ShareAnchor? from,
  ShareParams Function(Rect origin) params,
) async {
  final Future<void> before = _shareSheetFree;
  final Completer<void> mine = Completer<void>();
  _shareSheetFree = mine.future;
  try {
    await before;
    await showShareSheet(params(from?.origin ?? shareOrigin(null)));
  } finally {
    mine.complete();
  }
}

// Share folders in use: getting ready, or with their share sheet open.
final Set<String> _shareFoldersInUse = <String>{};
int _shareFolderCount = 0;

/// A folder for one share's files, kept until [finishShareFolder]. The
/// folders of earlier shares, finished by now, go: the app a file was
/// shared to may still read it after the share sheet closes, so each is
/// kept until the next share starts, or the next launch.
Future<Directory> _newShareFolder() async =>
    newShareFolderIn(await getTemporaryDirectory());

@visibleForTesting
Future<Directory> newShareFolderIn(Directory temp) async {
  final Directory shared = await Directory(
    '${temp.path}/$sharedFolderName',
  ).create(recursive: true);
  // In use from before it exists, so a share starting meanwhile keeps it.
  final Directory folder = Directory(
    '${shared.path}/${DateTime.now().microsecondsSinceEpoch}-'
    '${_shareFolderCount++}',
  );
  _shareFoldersInUse.add(folder.path);
  await for (final FileSystemEntity entity in shared.list()) {
    if (!_shareFoldersInUse.contains(entity.path)) {
      await deleteQuietly(entity);
    }
  }
  return folder.create();
}

/// [folder]'s share is done: the next share may delete it.
@visibleForTesting
void finishShareFolder(Directory folder) {
  _shareFoldersInUse.remove(folder.path);
}
