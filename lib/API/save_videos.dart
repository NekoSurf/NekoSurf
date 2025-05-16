import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_chan/Models/saved_attachment.dart';
import 'package:flutter_chan/blocs/saved_attachments_model.dart';
import 'package:flutter_chan/pages/savedAttachments/permission_denied.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
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

Future<Directory> requestDirectory(Directory directory, BuildContext context,
    {bool showErrorDialog = true}) async {
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
    if (await _requestPermission(Permission.photos)) {
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
  bool showSnackBar = false,
  bool isSaved = true,
}) async {
  final SavedAttachmentsProvider savedAttachmentsProvider =
      Provider.of<SavedAttachmentsProvider>(context, listen: false);

  savedAttachmentsProvider.pauseVideo();

  Directory directory = Directory('');

  if (isSaved) {
    try {
      directory = await requestDirectory(directory, context);
    } catch (e) {
      savedAttachmentsProvider.startVideo();
      return;
    }

    if (Platform.isIOS) {
      await ImageGallerySaverPlus.saveFile(
        '${directory.path}/savedAttachments/$fileName'
            .replaceAll('.webm', '.mp4'),
        isReturnPathOfIOS: true,
      ).then((value) => {
            if (showSnackBar)
              showCupertinoSnackbar(
                const Duration(milliseconds: 1800),
                true,
                context,
                'File saved!',
              )
            else
              null,
          });
    } else {
      await ImageGallerySaverPlus.saveFile(
        '${directory.path}/savedAttachments/$fileName'
            .replaceAll('.webm', '.mp4'),
        isReturnPathOfIOS: true,
      ).then((value) => {
            if (showSnackBar)
              showCupertinoSnackbar(
                const Duration(milliseconds: 1800),
                true,
                context,
                'File saved!',
              )
            else
              null,
          });
    }
  } else {
    try {
      directory = await requestDirectory(directory, context);
    } catch (e) {
      savedAttachmentsProvider.startVideo();
      return;
    }

    showCupertinoSnackbar(
      null,
      false,
      context,
      'Downloading...',
    );

    final String ext = '.${fileName.split('.').last}';

    try {
      if (await directory.exists()) {
        final File fileDownloadPath = File('${directory.path}/$fileName');
        final File videoCache = await DefaultCacheManager().getSingleFile(url);

        if (Platform.isIOS) {
          if (ext == '.webm') {
            Navigator.pop(context);
            showCupertinoSnackbar(
              null,
              false,
              context,
              'File converting...',
            );

            final ReturnCode? returnCode =
                await convertWebMToMP4(videoCache, fileDownloadPath);

            if (ReturnCode.isSuccess(returnCode)) {
              await ImageGallerySaverPlus.saveFile(
                fileDownloadPath.path.replaceAll('.webm', '.mp4'),
                isReturnPathOfIOS: true,
              ).then((value) => {
                    if (showSnackBar) Navigator.pop(context),
                    if (showSnackBar)
                      showCupertinoSnackbar(
                        const Duration(milliseconds: 1800),
                        true,
                        context,
                        'File downloaded!',
                      )
                    else
                      null,
                  });
            } else {
              Navigator.pop(context);
              showCupertinoSnackbar(
                const Duration(milliseconds: 1800),
                true,
                context,
                'Download failed :(',
              );
            }
          } else {
            await ImageGallerySaverPlus.saveFile(videoCache.path,
                    isReturnPathOfIOS: true)
                .then((value) => {
                      if (showSnackBar) Navigator.pop(context),
                      if (showSnackBar)
                        showCupertinoSnackbar(
                          const Duration(milliseconds: 1800),
                          true,
                          context,
                          'File downloaded!',
                        )
                      else
                        null,
                    });
          }
        } else {
          await ImageGallerySaverPlus.saveFile(
            videoCache.path,
          ).then((value) => {
                if (showSnackBar) Navigator.pop(context),
                if (showSnackBar)
                  showCupertinoSnackbar(
                    const Duration(milliseconds: 1800),
                    true,
                    context,
                    'File downloaded!',
                  )
                else
                  null,
              });
        }
      }
    } catch (e) {
      print(e);
      showCupertinoSnackbar(
        const Duration(milliseconds: 1800),
        true,
        context,
        'Download failed :(',
      );
    }
  }

  savedAttachmentsProvider.startVideo();
}

Future<void> shareMedia(
  String url,
  String fileName,
  BuildContext context, {
  bool isSaved = false,
}) async {
  Directory directory = Directory('');

  final SavedAttachmentsProvider savedAttachmentsProvider =
      Provider.of<SavedAttachmentsProvider>(context, listen: false);

  savedAttachmentsProvider.pauseVideo();

  if (isSaved) {
    try {
      directory = await requestDirectory(directory, context);
    } catch (e) {
      savedAttachmentsProvider.startVideo();
      return;
    }

    Share.shareXFiles([
      XFile(
        '${directory.path}/savedAttachments/$fileName'
            .replaceAll('.webm', '.mp4'),
      )
    ]);
  } else {
    try {
      directory = await requestDirectory(directory, context);
    } catch (e) {
      savedAttachmentsProvider.startVideo();
      return;
    }

    showCupertinoSnackbar(
      null,
      false,
      context,
      'Downloading...',
    );

    try {
      if (await directory.exists()) {
        final File fileDownloadPath = File('${directory.path}/$fileName');
        final File videoCache = await DefaultCacheManager().getSingleFile(url);

        final String ext = '.${fileName.split('.').last}';

        if (Platform.isIOS) {
          if (ext == '.webm') {
            Navigator.pop(context);
            showCupertinoSnackbar(
              null,
              false,
              context,
              'File converting...',
            );

            final ReturnCode? returnCode =
                await convertWebMToMP4(videoCache, fileDownloadPath);

            if (ReturnCode.isSuccess(returnCode)) {
              Navigator.pop(context);
              showCupertinoSnackbar(
                const Duration(milliseconds: 1000),
                true,
                context,
                'File downloaded!',
              ).then((value) => {
                    Share.shareXFiles([
                      XFile(
                        fileDownloadPath.path.replaceAll('.webm', '.mp4'),
                      )
                    ]),
                  });
            } else {
              Navigator.pop(context);
              showCupertinoSnackbar(
                const Duration(milliseconds: 1800),
                true,
                context,
                'Download failed :(',
              );
            }
          } else {
            Navigator.pop(context);
            showCupertinoSnackbar(
              const Duration(milliseconds: 1000),
              true,
              context,
              'File downloaded!',
            ).then((value) => {
                  Share.shareXFiles([
                    XFile(videoCache.path),
                  ])
                });
          }
        } else {
          Navigator.pop(context);
          Share.shareXFiles([
            XFile(videoCache.path),
          ]);
        }
      }
    } catch (e) {
      print(e);
    }
  }

  savedAttachmentsProvider.startVideo();
}

Future<SavedAttachment?> saveAttachment(
  String url,
  String thumbnailUrl,
  String fileName,
  BuildContext context,
  SavedAttachmentsProvider savedAttachmentsProvider,
) async {
  Directory directory = Directory('');
  final dio = Dio();

  final SavedAttachmentsProvider savedAttachmentsProvider =
      Provider.of<SavedAttachmentsProvider>(context, listen: false);

  savedAttachmentsProvider.pauseVideo();

  try {
    directory = await requestDirectory(directory, context);
  } catch (e) {
    savedAttachmentsProvider.startVideo();
    return null;
  }

  showCupertinoSnackbar(
    null,
    false,
    context,
    'Downloading...',
  );

  try {
    if (await directory.exists()) {
      final File fileDownloadPath =
          File('${directory.path}/savedAttachments/$fileName');
      final File videoCache = await DefaultCacheManager().getSingleFile(url);

      final Directory savedAttachmentsDirectory =
          Directory('${directory.path}/savedAttachments');

      if (!await savedAttachmentsDirectory.exists()) {
        await savedAttachmentsDirectory.create(recursive: true);
      }

      final String ext = '.${fileName.split('.').last}';

      if (Platform.isIOS) {
        Navigator.pop(context);
        if (ext == '.webm') {
          showCupertinoSnackbar(
            null,
            false,
            context,
            'File converting...',
          );

          final ReturnCode? returnCode =
              await convertWebMToMP4(videoCache, fileDownloadPath);

          if (ReturnCode.isSuccess(returnCode)) {
            final String thumbnailPath = await downloadThumbnail(
              fileName,
              thumbnailUrl,
              '${directory.path}/savedAttachments/',
              dio,
            );

            Navigator.pop(context);

            showCupertinoSnackbar(
              const Duration(milliseconds: 1800),
              true,
              context,
              'File downloaded!',
            );

            savedAttachmentsProvider.startVideo();

            return SavedAttachment(
              savedAttachmentType: SavedAttachmentType.Video,
              fileName: fileName.replaceAll('.webm', '.mp4'),
              thumbnail: thumbnailPath,
            );
          } else {
            savedAttachmentsProvider.startVideo();

            showCupertinoSnackbar(
              const Duration(milliseconds: 1800),
              true,
              context,
              'Download failed :(',
            );

            return null;
          }
        } else {
          videoCache.copy(fileDownloadPath.path);

          if (ext == '.mp4') {
            final String thumbnailPath = await downloadThumbnail(
              fileName,
              thumbnailUrl,
              '${directory.path}/savedAttachments/',
              dio,
            );

            Navigator.pop(context);

            showCupertinoSnackbar(
              const Duration(milliseconds: 1800),
              true,
              context,
              'File downloaded!',
            );

            savedAttachmentsProvider.startVideo();

            return SavedAttachment(
              savedAttachmentType: SavedAttachmentType.Video,
              fileName: fileName,
              thumbnail: thumbnailPath,
            );
          } else {
            showCupertinoSnackbar(
              const Duration(milliseconds: 1800),
              true,
              context,
              'File downloaded!',
            );

            savedAttachmentsProvider.startVideo();

            return SavedAttachment(
              savedAttachmentType: ext == '.mp4'
                  ? SavedAttachmentType.Video
                  : SavedAttachmentType.Image,
              fileName: fileName,
              thumbnail: fileName,
            );
          }
        }
      } else {
        videoCache.copy(fileDownloadPath.path);

        String thumbnailPath = fileName;

        if (ext == '.mp4' || ext == '.webm') {
          thumbnailPath = await downloadThumbnail(
            fileName,
            thumbnailUrl,
            '${directory.path}/savedAttachments/',
            dio,
          );
        }

        Navigator.pop(context);

        showCupertinoSnackbar(
          const Duration(milliseconds: 1800),
          true,
          context,
          'File downloaded!',
        );

        savedAttachmentsProvider.startVideo();

        return SavedAttachment(
          savedAttachmentType: ext == '.mp4' || ext == '.webm' || ext == '.gif'
              ? SavedAttachmentType.Video
              : SavedAttachmentType.Image,
          fileName: fileName,
          thumbnail: thumbnailPath,
        );
      }
    }

    savedAttachmentsProvider.startVideo();

    return null;
  } catch (e) {
    print(e);

    savedAttachmentsProvider.startVideo();

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

  await dio.download(
    thumbnailUrl,
    '$path$nameWithoutExtension.jpg',
  );

  return '$nameWithoutExtension.jpg';
}

String getNameWithoutExtension(String fileName) {
  if (fileName.contains('.')) {
    return fileName.substring(0, fileName.lastIndexOf('.'));
  } else {
    return fileName;
  }
}
