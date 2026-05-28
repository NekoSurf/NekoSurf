import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
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
    }
  } else {
    if (await _requestPermission(Permission.photosAddOnly)) {
      directory = await getApplicationDocumentsDirectory();
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
      return sdkInt >= 29 ? true : await Permission.storage.request().isGranted;
    }
  } else if (Platform.isIOS) {
    return skipIfExists
        ? await Permission.photos.request().isGranted
        : await Permission.photosAddOnly.request().isGranted;
  }

  return false; // Unsupported platforms
}

Future<ReturnCode?> convertWebMToMP4(File webmFile, File mp4File) async {
  mp4File = File(mp4File.path.replaceAll('.webm', '.mp4'));

  final FFmpegSession session = await FFmpegKit.execute(
    '-y -i ${webmFile.path} -c:v mpeg4 -qscale 0 ${mp4File.path}',
  );

  return session.getReturnCode();
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
      final String savedPath =
          '${directory.path}/savedAttachments/$savedName';
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

      await SaverGallery.saveFile(
        filePath: savedPath,
        fileName: savedName,
        skipIfExists: false,
      );
      return;
    }

    final File videoCache = await DefaultCacheManager().getSingleFile(url);
    final String ext = '.${fileName.split('.').last}'.toLowerCase();

    if (Platform.isIOS && ext == '.webm') {
      final String outputName = toMp4Name(fileName);
      final File outputFile = File('${directory.path}/$outputName');

      final ReturnCode? returnCode = await convertWebMToMP4(
        videoCache,
        outputFile,
      );

      if (!ReturnCode.isSuccess(returnCode)) {
        throw Exception('webm conversion failed');
      }

      await SaverGallery.saveFile(
        filePath: outputFile.path,
        fileName: outputName,
        skipIfExists: false,
      );
      return;
    }

    await SaverGallery.saveFile(
      filePath: videoCache.path,
      fileName: fileName,
      skipIfExists: false,
    );
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
    final String savedPath = '${directory.path}/savedAttachments/$savedName';
    await SharePlus.instance.share(ShareParams(files: [XFile(savedPath)]));
    return;
  }

  try {
    if (!await directory.exists()) {
      return;
    }

    final File videoCache = await DefaultCacheManager().getSingleFile(url);
    final String ext = '.${fileName.split('.').last}'.toLowerCase();

    if (Platform.isIOS && ext == '.webm') {
      final File fileDownloadPath = File('${directory.path}/$fileName');
      final ReturnCode? returnCode = await convertWebMToMP4(
        videoCache,
        fileDownloadPath,
      );

      if (ReturnCode.isSuccess(returnCode)) {
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
      ShareParams(files: [XFile(videoCache.path)]),
    );
  } catch (e) {
    debugPrint('shareMedia error: $e');
  }
}

Future<SavedAttachment?> saveAttachment(
  String url,
  String thumbnailUrl,
  String fileName,
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

    final Directory savedDir = Directory(
      '${baseDirectory.path}/savedAttachments',
    );
    if (!await savedDir.exists()) {
      await savedDir.create(recursive: true);
    }

    final File cachedFile = await DefaultCacheManager().getSingleFile(url);
    final String ext = '.${fileName.split('.').last}'.toLowerCase();

    String finalFileName = fileName;
    String thumbnailPath = fileName;

    final bool isVideoLike = ext == '.mp4' || ext == '.webm' || ext == '.gif';

    if (Platform.isIOS && ext == '.webm') {
      final File outputFile = File('${savedDir.path}/$fileName');
      final ReturnCode? returnCode = await convertWebMToMP4(
        cachedFile,
        outputFile,
      );

      if (!ReturnCode.isSuccess(returnCode)) {
        return null;
      }

      finalFileName = fileName.replaceAll('.webm', '.mp4');
      thumbnailPath = await downloadThumbnail(
        fileName,
        thumbnailUrl,
        '${savedDir.path}/',
        dio,
      );
    } else {
      final File outputFile = File('${savedDir.path}/$fileName');
      await cachedFile.copy(outputFile.path);

      if (isVideoLike) {
        thumbnailPath = await downloadThumbnail(
          fileName,
          thumbnailUrl,
          '${savedDir.path}/',
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
    );
  } catch (e, st) {
    debugPrint('saveAttachment error: $e\n$st');
    return null;
  }
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
