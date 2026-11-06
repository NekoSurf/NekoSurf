import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chan/chan/http_client.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/media/video_server.dart';
import 'package:flutter_chan/saved/saved_attachment.dart';
import 'package:flutter_chan/saved/saved_folders.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// How far along a save or share is, from 0 to 1; null while that's
/// unknown. It covers downloading the file and, for a webm on iPhone,
/// converting it ([SaveSteps]); handing it to Photos or the share sheet
/// says nothing, so it stays full meanwhile.
typedef SaveProgress = void Function(double? progress);

/// [progress] in whole percent: a ring can't show finer, and it's fewer
/// rebuilds.
double? _wholePercent(double? progress) =>
    progress == null ? null : (progress.clamp(0, 1) * 100).floor() / 100;

/// iPhones can't play webms, so what's saved or shared is converted first.
bool _converts(String fileName) =>
    Platform.isIOS && fileName.toLowerCase().endsWith('.webm');

String _withMp4Extension(String name) => name.toLowerCase().endsWith('.webm')
    ? '${name.substring(0, name.length - 5)}.mp4'
    : name;

/// The extension of the file saving [uploadName] leaves, as it's converted or
/// not.
@visibleForTesting
String savedExtension(String uploadName) {
  final String ext = '.${uploadName.split('.').last}'.toLowerCase();
  return _converts(uploadName) ? _withMp4Extension(ext) : ext;
}

/// One ring over a save's steps: downloading, then, if it [converts],
/// converting, half each. With nothing to download (a video already
/// watched), converting fills all of it.
@visibleForTesting
class SaveSteps {
  SaveSteps(this._onProgress, {required bool converts}) : _converts = converts;

  final SaveProgress? _onProgress;
  final bool _converts;
  bool _downloaded = false;

  /// The download's progress; null (size unknown) keeps what's showing.
  void download(double? progress) {
    if (progress == null) {
      return;
    }
    _downloaded = true;
    _report(_converts ? progress / 2 : progress);
  }

  /// The conversion's progress; null if it can't tell (a spinner).
  void convert(double? progress) {
    if (progress == null) {
      _onProgress?.call(null);
      return;
    }
    _report(_downloaded ? 0.5 + progress / 2 : progress);
  }

  void _report(double progress) => _onProgress?.call(_wholePercent(progress));
}

/// Converts a webm to an H.264 mp4 with the hardware encoder (iOS only).
/// It needs more bits than VP9 for the same picture: at twice the webm's
/// bitrate it's about as close to the webm as MPEG-4 at -qscale 0 was, at
/// a fraction of that size.
///
/// H.264 stores 4:2:0 video in whole pairs of pixels, and webms are often an
/// odd size (853x480), so a stray last column or row is cropped off.
///
/// [onProgress] hears how much of the video is converted, from 0 to 1, as
/// ffmpeg reports the time it's up to; null if the webm doesn't say how
/// long it is.
Future<void> _convertWebMToMP4(
  File webmFile,
  File mp4File,
  void Function(double? progress) onProgress,
) async {
  final (int? sourceBitrate, int? durationMs) = await _probe(webmFile);
  final int bitrate = sourceBitrate == null ? 4000000 : 2 * sourceBitrate;

  onProgress(durationMs == null ? null : 0);
  // yuv420p + aac keep the mp4 compatible with the Photos library.
  final FFmpegSession session = await FFmpegKit.executeAsync(
    '-y -i "${webmFile.path}" -vf "crop=trunc(iw/2)*2:trunc(ih/2)*2:0:0" -c:v h264_videotoolbox -allow_sw 1 -b:v $bitrate -pix_fmt yuv420p -c:a aac "${mp4File.path}"',
    onStatistics: durationMs == null
        ? null
        : (Statistics statistics) =>
              onProgress((statistics.time / durationMs).clamp(0, 1)),
  );

  if (session.getReturnCode() != 0) {
    throw Exception('webm conversion failed');
  }
  // ffmpeg's last report stops a frame or so short of the length.
  onProgress(1);
}

/// [file]'s overall bitrate in bits per second and its length in
/// milliseconds, each null if ffprobe can't tell.
Future<(int?, int?)> _probe(File file) async {
  try {
    final FFprobeSession session = await FFprobeKit.getMediaInformationAsync(
      file.path,
    );
    final MediaInformation? info = session.getMediaInformation();
    final double? seconds = double.tryParse(info?.duration ?? '');
    return (
      int.tryParse(info?.bitrate ?? ''),
      seconds == null || seconds <= 0 ? null : (seconds * 1000).round(),
    );
  } catch (e) {
    debugPrint('probe failed for ${file.path}: $e');
    return (null, null);
  }
}

/// What saving or sharing [url] gives out: downloaded into [folder] under a
/// safe name and, for a webm on iPhone, converted to an mp4.
Future<File> downloadToGive(
  Directory folder,
  String url,
  String fileName,
  SaveProgress? onProgress,
) async {
  final bool converts = _converts(fileName);
  final SaveSteps steps = SaveSteps(onProgress, converts: converts);
  final File downloaded = await downloadInto(
    folder,
    url,
    localFileName(fileName),
    onProgress: steps.download,
  );
  if (!converts) {
    return downloaded;
  }
  final File mp4 = File(_withMp4Extension(downloaded.path));
  await _convertWebMToMP4(downloaded, mp4, steps.convert);
  await deleteQuietly(downloaded);
  return mp4;
}

/// Downloads [post]'s upload into [folders] for the Saved tab, in a file called
/// [diskName]; a failed save leaves no file behind.
Future<SavedAttachment> downloadToSaved(
  SavedFolders folders,
  Post post, {
  required String diskName,
  SaveProgress? onProgress,
}) async {
  final String uploadName = post.uploadName;
  final bool converts = _converts(uploadName);
  final SaveSteps steps = SaveSteps(onProgress, converts: converts);
  final String ext = savedExtension(uploadName);

  String? savedName;
  File? output;
  Directory? work;
  try {
    work = await newWorkFolder();
    final File downloaded = await downloadInto(
      work,
      post.fileUrl,
      uploadName,
      onProgress: steps.download,
    );

    savedName =
        await uniqueSavedFileName(
          folders.media,
          diskName,
          ext,
          reserve: true,
        ) ??
        '${post.tim}$ext';
    output = File(folders.pathOfFile(savedName));
    if (converts) {
      await _convertWebMToMP4(downloaded, output, steps.convert);
    } else {
      await downloaded.copy(output.path);
    }

    final SavedAttachment attachment = SavedAttachment(
      type: isVideoFileName(uploadName)
          ? SavedAttachmentType.video
          : SavedAttachmentType.image,
      fileName: savedName,
      thumbnail: isVideoFileName(uploadName)
          ? await _videoThumbnail(output.path, post, folders.thumbnails)
          : savedName,
      id: post.uploadId,
    );
    output = null;
    return attachment;
  } finally {
    if (output != null) {
      // A half-converted or unlisted file would linger in Files.
      await deleteQuietly(output);
    }
    if (savedName != null) {
      // Written (and found by name from now on), or deleted.
      releaseSavedFileName(folders.media, savedName);
    }
    if (work != null) {
      await deleteQuietly(work);
    }
  }
}

/// Grabs a frame from the video itself; falls back to 4chan's tiny 125px thumb.
Future<String> _videoThumbnail(
  String videoPath,
  Post post,
  String thumbsDir,
) async {
  final String thumbName = '${post.tim}.jpg';
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
  await downloadThumbnail(post.thumbnailUrl, out);
  return thumbName;
}

// Saving and sharing download and convert in folders of their own in the
// temporary directory, so they can't overwrite each other's files, and
// what they leave there can be found and deleted.
const String _workingFolderName = 'working';
const String sharedFolderName = 'shared';

/// 4chan's file types. Older versions downloaded and converted right in the
/// temporary directory, and left the files there.
const List<String> _mediaExtensions = [
  '.jpg',
  '.png',
  '.gif',
  '.webm',
  '.mp4',
  '.pdf',
];

/// A folder for one save's files, deleted by the save when it's done.
Future<Directory> newWorkFolder() async {
  final Directory temp = await getTemporaryDirectory();
  final Directory working = await Directory(
    '${temp.path}/$_workingFolderName',
  ).create(recursive: true);
  return working.createTemp();
}

Future<void> deleteQuietly(FileSystemEntity entity) async {
  try {
    await entity.delete(recursive: true);
  } on FileSystemException {
    // Gone already.
  }
}

/// Deletes what saving and sharing left in the temporary directory. Meant
/// for launch, when nothing is being saved or shared.
Future<void> deleteSaveLeftovers() async {
  try {
    await deleteSaveLeftoversIn(await getTemporaryDirectory());
  } catch (e) {
    debugPrint('deleteSaveLeftovers error: $e');
  }
}

@visibleForTesting
Future<void> deleteSaveLeftoversIn(Directory temp) async {
  await for (final FileSystemEntity entity in temp.list()) {
    final String name = entity.path.split('/').last;
    final bool isLeftover = entity is Directory
        ? name == _workingFolderName || name == sharedFolderName
        : _mediaExtensions.any(name.toLowerCase().endsWith);
    if (isLeftover) {
      await deleteQuietly(entity);
    }
  }
}

/// Puts [url] into [folder] as [fileName]: copied from the video cache when
/// it was watched already, or once the player's download of it is done,
/// otherwise downloaded. [onProgress] hears how far along either download
/// is, in whole percent.
@visibleForTesting
Future<File> downloadInto(
  Directory folder,
  String url,
  String fileName, {
  SaveProgress? onProgress,
}) async {
  void report(double? progress) => onProgress?.call(_wholePercent(progress));
  final File file = File('${folder.path}/$fileName');
  final File? cached = await VideoServer.instance.downloadedFile(
    url,
    onProgress: report,
  );
  if (cached != null) {
    try {
      return await cached.copy(file.path);
    } catch (_) {
      // Pruned meanwhile: download it after all.
    }
  }
  await _download(url, file, onProgress: report);
  return file;
}

// Tries per download. Several saves at once can make 4chan answer 429 (too
// many requests); like the player's downloads, they wait and try again.
const int _downloadAttempts = 3;

/// The wait before a download's second try; it doubles after that, and
/// again when 4chan said 429.
@visibleForTesting
Duration downloadRetryDelay = const Duration(seconds: 2);

/// Downloads [url] into [file], trying again after a 429, a server error
/// or a dropped connection; leaves no partial file behind on failure.
Future<void> _download(
  String url,
  File file, {
  SaveProgress? onProgress,
}) async {
  for (int attempt = 1; ; attempt++) {
    try {
      await _downloadOnce(url, file, onProgress);
      return;
    } catch (e) {
      final int? status = e is _DownloadStatus ? e.status : null;
      final bool retryable = status == null
          ? e is! FileSystemException
          : status == 429 || status >= 500;
      if (!retryable || attempt >= _downloadAttempts) {
        rethrow;
      }
      await Future<void>.delayed(
        downloadRetryDelay * ((1 << (attempt - 1)) * (status == 429 ? 2 : 1)),
      );
    }
  }
}

class _DownloadStatus extends HttpException {
  _DownloadStatus(this.status, Uri uri) : super('HTTP $status', uri: uri);

  final int status;
}

Future<void> _downloadOnce(
  String url,
  File file,
  SaveProgress? onProgress,
) async {
  final Uri uri = Uri.parse(url);
  try {
    final http.StreamedResponse response = await httpClient.send(
      http.Request('GET', uri),
    );
    if (response.statusCode != HttpStatus.ok) {
      // Read to the end, or the connection isn't reused.
      await response.stream.drain<void>();
      throw _DownloadStatus(response.statusCode, uri);
    }
    final int? total = response.contentLength;
    int received = 0;
    onProgress?.call(total == null || total == 0 ? null : 0);
    final IOSink sink = file.openWrite();
    try {
      await sink.addStream(
        response.stream.map((List<int> chunk) {
          received += chunk.length;
          if (total != null && total > 0) {
            onProgress?.call(received / total);
          }
          return chunk;
        }),
      );
    } finally {
      await sink.close();
    }
  } catch (_) {
    if (await file.exists()) {
      await file.delete();
    }
    rethrow;
  }
}

/// Downloads a thumbnail into [file], leaving no partial file on failure.
@visibleForTesting
Future<void> downloadThumbnail(String url, File file) => _download(url, file);
