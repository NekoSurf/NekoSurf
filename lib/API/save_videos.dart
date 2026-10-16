import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/saved_attachment.dart';
import 'package:flutter_chan/blocs/saved_attachments_model.dart';
import 'package:flutter_chan/pages/savedAttachments/permission_denied.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';

import '../services/show_snackbar.dart';

Future<bool> _requestPermission(Permission permission) async {
  if (await permission.isGranted) {
    return true;
  } else {
    final result = await permission.request();
    if (result == PermissionStatus.granted) {
      return true;
    }
  }
  return false;
}

// Thumbnails live in the app-private Application Support dir so they never show
// up in Files / the Download folder. iOS media sits in the Documents root.
String _thumbnailsDir = '';

String savedMediaDirPath(String base) =>
    Platform.isIOS ? base : '$base/savedAttachments';

String savedMediaPath(String base, String fileName) =>
    '${savedMediaDirPath(base)}/$fileName';

/// Images use themselves as thumbnail, so only video thumbnails are relocated.
String savedThumbnailPath(String base, SavedAttachment attachment) {
  final String thumb = attachment.thumbnail ?? attachment.fileName ?? '';
  if (thumb == attachment.fileName) {
    return savedMediaPath(base, thumb);
  }
  return '$_thumbnailsDir/$thumb';
}

Future<String> _ensureThumbnailsDir() async {
  if (_thumbnailsDir.isEmpty) {
    final Directory support = await getApplicationSupportDirectory();
    _thumbnailsDir = '${support.path}/savedThumbnails';
  }
  await Directory(_thumbnailsDir).create(recursive: true);
  return _thumbnailsDir;
}

Future<Directory> requestDirectory(
  Directory directory,
  BuildContext context, {
  bool showErrorDialog = true,
}) async {
  if (Platform.isAndroid) {
    final int sdkVersion =
        (await DeviceInfoPlugin().androidInfo).version.sdkInt;

    final permission = sdkVersion >= 30
        ? Permission.manageExternalStorage
        : Permission.storage;

    if (await _requestPermission(permission)) {
      directory = (await getExternalStorageDirectory())!;
      String newPath = '';
      final List<String> paths = directory.path.split('/');
      for (int x = 1; x < paths.length; x++) {
        final String folder = paths[x];
        if (folder != 'Android') {
          newPath += '/$folder';
        } else {
          break;
        }
      }
      newPath = '$newPath/Download/4Chan';
      directory = Directory(newPath);
      await _ensureThumbnailsDir();
    }
  } else {
    if (await _requestPermission(Permission.photosAddOnly)) {
      directory = await getApplicationDocumentsDirectory();
      await _ensureThumbnailsDir();
    } else {
      if (showErrorDialog) {
        await showCupertinoModalBottomSheet(
          expand: false,
          context: context,
          builder: (context) => const PermissionDenied(),
        );
      }
      throw 'Permission denied';
    }
  }

  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }

  return directory;
}

Future<bool> checkAndRequestPermissions({required bool skipIfExists}) async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return false;
  }

  if (Platform.isAndroid) {
    final deviceInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = deviceInfo.version.sdkInt;

    if (skipIfExists) {
      // Read permission is required to check if the file already exists
      return sdkInt >= 33
          ? await Permission.photos.request().isGranted
          : await Permission.storage.request().isGranted;
    } else {
      // No read permission required for Android SDK 29 and above
      return sdkInt >= 29 || await Permission.storage.request().isGranted;
    }
  } else if (Platform.isIOS) {
    return skipIfExists
        ? await Permission.photos.request().isGranted
        : await Permission.photosAddOnly.request().isGranted;
  }

  return false; // Unsupported platforms
}

Future<int> convertWebMToMP4(File webmFile, File mp4File) async {
  mp4File = File(mp4File.path.replaceAll('.webm', '.mp4'));

  // yuv420p + aac keep the mp4 compatible with the Photos library.
  final FFmpegSession session = await FFmpegKit.executeAsync(
    '-y -i "${webmFile.path}" -c:v mpeg4 -qscale 0 -pix_fmt yuv420p -c:a aac "${mp4File.path}"',
  );

  return session.getReturnCode();
}

/// saver_gallery never answers on iOS for videos Photos rejects, so cap the wait.
Future<bool> _saveToGallery(String path, String name) async {
  try {
    final result = await SaverGallery.saveFile(
      filePath: path,
      fileName: name,
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

Future<void> saveVideo(
  String url,
  String fileName,
  BuildContext context, {
  bool isSaved = true,
}) async {
  final bool hasPermission = await checkAndRequestPermissions(
    skipIfExists: false,
  );

  if (!hasPermission) {
    showCupertinoSnackbar(
      const Duration(milliseconds: 1800),
      true,
      context,
      'Permission denied',
    );
    return;
  }

  String toMp4Name(String name) {
    return name.toLowerCase().endsWith('.webm')
        ? '${name.substring(0, name.length - 5)}.mp4'
        : name;
  }

  Directory directory;

  try {
    directory = await requestDirectory(
      Directory(''),
      context,
      showErrorDialog: false,
    );
  } catch (_) {
    showCupertinoSnackbar(
      const Duration(milliseconds: 1800),
      true,
      context,
      'Download failed :(',
    );
    return;
  }

  try {
    if (isSaved) {
      // On iOS, saved attachments are converted from .webm to .mp4
      // On Android, they remain as .webm
      final String savedName = Platform.isIOS ? toMp4Name(fileName) : fileName;
      final String savedPath = savedMediaPath(directory.path, savedName);
      final File savedFile = File(savedPath);

      if (!await savedFile.exists()) {
        showCupertinoSnackbar(
          const Duration(milliseconds: 1800),
          true,
          context,
          'File not found',
        );
        return;
      }

      if (!await _saveToGallery(savedPath, savedName)) {
        throw Exception('gallery save failed');
      }
      return;
    }

    final File downloadedFile = await _downloadToTemp(url, fileName);
    final String ext = '.${fileName.split('.').last}'.toLowerCase();

    if (Platform.isIOS && ext == '.webm') {
      final String outputName = toMp4Name(fileName);
      final File outputFile = File('${downloadedFile.parent.path}/$outputName');

      final returnCode = await convertWebMToMP4(downloadedFile, outputFile);

      if (returnCode != 0) {
        throw Exception('webm conversion failed');
      }

      if (!await _saveToGallery(outputFile.path, outputName)) {
        throw Exception('gallery save failed');
      }
      return;
    }

    if (!await _saveToGallery(downloadedFile.path, fileName)) {
      throw Exception('gallery save failed');
    }
  } catch (e) {
    debugPrint('saveVideo error: $e');
    showCupertinoSnackbar(
      const Duration(milliseconds: 1800),
      true,
      context,
      'Download failed :(',
    );
  }
}

/// Saves already-saved attachments to Photos/gallery; returns the number that failed.
Future<int> saveSavedAttachmentsToGallery(
  List<String> fileNames,
  BuildContext context,
) async {
  if (!await checkAndRequestPermissions(skipIfExists: false)) {
    if (context.mounted) {
      showCupertinoSnackbar(
        const Duration(milliseconds: 1800),
        true,
        context,
        'Permission denied',
      );
    }
    return fileNames.length;
  }

  final Directory directory;
  try {
    directory = await requestDirectory(
      Directory(''),
      context,
      showErrorDialog: false,
    );
  } catch (_) {
    return fileNames.length;
  }

  int failed = 0;
  for (final fileName in fileNames) {
    final String savedName = Platform.isIOS
        ? fileName.replaceAll('.webm', '.mp4')
        : fileName;
    final String savedPath = savedMediaPath(directory.path, savedName);
    try {
      if (!await File(savedPath).exists()) {
        failed++;
        continue;
      }
      if (!await _saveToGallery(savedPath, savedName)) {
        failed++;
      }
    } catch (e) {
      debugPrint('saveSavedAttachmentsToGallery error: $e');
      failed++;
    }
  }
  return failed;
}

/// Opens one share sheet for all given saved attachments (includes "Save to Files").
Future<void> shareSavedAttachments(
  List<String> fileNames,
  BuildContext context,
) async {
  final Directory directory;
  try {
    directory = await requestDirectory(Directory(''), context);
  } catch (_) {
    return;
  }

  final files = <XFile>[];
  for (final fileName in fileNames) {
    final String savedName = Platform.isIOS
        ? fileName.replaceAll('.webm', '.mp4')
        : fileName;
    final String savedPath = savedMediaPath(directory.path, savedName);
    if (await File(savedPath).exists()) {
      files.add(XFile(savedPath));
    }
  }
  if (files.isEmpty) {
    return;
  }
  await SharePlus.instance.share(ShareParams(files: files));
}

Future<void> shareMedia(
  String url,
  String fileName,
  BuildContext context, {
  bool isSaved = false,
}) async {
  Directory directory;
  try {
    directory = await requestDirectory(Directory(''), context);
  } catch (_) {
    return;
  }

  if (isSaved) {
    // On iOS, saved attachments are converted from .webm to .mp4
    // On Android, they remain as .webm
    final String savedName = Platform.isIOS
        ? fileName.replaceAll('.webm', '.mp4')
        : fileName;
    final String savedPath = savedMediaPath(directory.path, savedName);
    await SharePlus.instance.share(ShareParams(files: [XFile(savedPath)]));
    return;
  }

  try {
    if (!await directory.exists()) {
      return;
    }

    final File downloadedFile = await _downloadToTemp(url, fileName);
    final String ext = '.${fileName.split('.').last}'.toLowerCase();

    if (Platform.isIOS && ext == '.webm') {
      final File fileDownloadPath = File(
        '${downloadedFile.parent.path}/$fileName',
      );
      final int returnCode = await convertWebMToMP4(
        downloadedFile,
        fileDownloadPath,
      );

      if (returnCode == 0) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(fileDownloadPath.path.replaceAll('.webm', '.mp4'))],
          ),
        );
      } else {
        showCupertinoSnackbar(
          const Duration(milliseconds: 1800),
          true,
          context,
          'Download failed :(',
        );
      }
      return;
    }

    await SharePlus.instance.share(
      ShareParams(files: [XFile(downloadedFile.path)]),
    );
  } catch (e) {
    debugPrint('shareMedia error: $e');
  }
}

Future<SavedAttachment?> saveAttachment(
  String url,
  String thumbnailUrl,
  String fileName,
  String displayName,
  BuildContext context,
  SavedAttachmentsProvider savedAttachmentsProvider,
) async {
  final Dio dio = Dio();

  try {
    final Directory baseDirectory = await requestDirectory(
      Directory(''),
      context,
    );
    if (!await baseDirectory.exists()) {
      return null;
    }

    final Directory savedDir = Directory(savedMediaDirPath(baseDirectory.path));
    if (!await savedDir.exists()) {
      await savedDir.create(recursive: true);
    }
    final String thumbsDir = await _ensureThumbnailsDir();

    final File downloadedFile = await _downloadToTemp(url, fileName, dio: dio);
    final String ext = '.${fileName.split('.').last}'.toLowerCase();

    String finalFileName = fileName;
    String thumbnailPath = fileName;

    final bool isVideoLike = ext == '.mp4' || ext == '.webm' || ext == '.gif';
    final String targetExt = Platform.isIOS && ext == '.webm' ? '.mp4' : ext;
    final String savedName =
        await uniqueSavedFileName(savedDir.path, displayName, targetExt) ??
        fileName.replaceAll('.webm', targetExt);

    if (Platform.isIOS && ext == '.webm') {
      final File outputFile = File('${savedDir.path}/$savedName');
      final int returnCode = await convertWebMToMP4(downloadedFile, outputFile);

      if (returnCode != 0) {
        return null;
      }

      finalFileName = savedName;
      thumbnailPath = await _videoThumbnail(
        '${savedDir.path}/$finalFileName',
        fileName,
        thumbnailUrl,
        thumbsDir,
        dio,
      );
    } else {
      final File outputFile = File('${savedDir.path}/$savedName');
      await downloadedFile.copy(outputFile.path);
      finalFileName = savedName;
      thumbnailPath = savedName;

      if (isVideoLike) {
        thumbnailPath = await _videoThumbnail(
          outputFile.path,
          fileName,
          thumbnailUrl,
          thumbsDir,
          dio,
        );
      }
    }

    return SavedAttachment(
      savedAttachmentType: isVideoLike
          ? SavedAttachmentType.Video
          : SavedAttachmentType.Image,
      fileName: finalFileName,
      thumbnail: thumbnailPath,
      id: getNameWithoutExtension(fileName),
    );
  } catch (e, st) {
    debugPrint('saveAttachment error: $e\n$st');
    return null;
  }
}

/// Uploader-facing on-disk name (e.g. "cat.mp4"), unique within [dir]; null if unusable.
Future<String?> uniqueSavedFileName(
  String dir,
  String originalName,
  String ext,
) async {
  final String base = getNameWithoutExtension(
    originalName,
  ).replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  if (base.isEmpty || base.startsWith('.')) {
    return null;
  }
  final String clipped = base.length > 100 ? base.substring(0, 100) : base;

  String candidate = '$clipped$ext';
  for (int n = 2; await File('$dir/$candidate').exists(); n++) {
    candidate = '$clipped ($n)$ext';
  }
  return candidate;
}

/// Grabs a frame from the video itself; falls back to 4chan's tiny 125px thumb.
Future<String> _videoThumbnail(
  String videoPath,
  String fileName,
  String thumbnailUrl,
  String thumbsDir,
  Dio dio,
) async {
  final String thumbName = '${getNameWithoutExtension(fileName)}.jpg';
  final File out = File('$thumbsDir/$thumbName');
  try {
    // Seeking past the end of very short clips yields no frame, so retry from 0.
    for (final String seek in ['-ss 0.5', '']) {
      final FFmpegSession session = await FFmpegKit.executeAsync(
        '-y $seek -i "$videoPath" -frames:v 1 -vf scale=480:-2 -q:v 3 "${out.path}"',
      );
      if (session.getReturnCode() == 0 &&
          await out.exists() &&
          await out.length() > 0) {
        return thumbName;
      }
    }
  } catch (e) {
    debugPrint('thumbnail extraction failed: $e');
  }
  return downloadThumbnail(fileName, thumbnailUrl, '$thumbsDir/', dio);
}

/// Downloads [url] into the temporary directory without any caching.
Future<File> _downloadToTemp(String url, String fileName, {Dio? dio}) async {
  final Directory tempDir = await getTemporaryDirectory();
  final File file = File('${tempDir.path}/$fileName');
  await (dio ?? Dio()).download(url, file.path);
  return file;
}

Future<String> downloadThumbnail(
  String fileName,
  String thumbnailUrl,
  String path,
  Dio dio,
) async {
  final String nameWithoutExtension = getNameWithoutExtension(fileName);

  await dio.download(thumbnailUrl, '$path$nameWithoutExtension.jpg');

  return '$nameWithoutExtension.jpg';
}

String getNameWithoutExtension(String fileName) {
  if (fileName.contains('.')) {
    return fileName.substring(0, fileName.lastIndexOf('.'));
  } else {
    return fileName;
  }
}
