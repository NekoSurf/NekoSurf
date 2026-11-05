import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/http_client.dart';
import 'package:flutter_chan/Models/saved_attachment.dart';
import 'package:flutter_chan/blocs/saved_attachments_model.dart';
import 'package:flutter_chan/pages/savedAttachments/permission_denied.dart';
import 'package:flutter_chan/services/video_server.dart';
import 'package:http/http.dart' as http;
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';

import '../services/show_snackbar.dart';

/// How far along a save or share is, from 0 to 1; null while that's
/// unknown. It covers downloading the file and, for a webm on iPhone,
/// converting it ([SaveSteps]); handing it to Photos or the share sheet
/// says nothing, so it stays full meanwhile.
typedef SaveProgress = void Function(double? progress);

/// [progress] in whole percent: a ring can't show finer, and it's fewer
/// rebuilds.
double? _wholePercent(double? progress) =>
    progress == null ? null : (progress.clamp(0, 1) * 100).floor() / 100;

/// Whether saving or sharing [fileName] converts it: webms on iPhone.
bool _converts(String fileName) =>
    Platform.isIOS && fileName.toLowerCase().endsWith('.webm');

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

/// Where saved media lives.
///
/// On iOS that's the app's own Documents folder (browsable in Files),
/// which needs no permission; Photos access is only asked for when saving
/// to the photo library. On Android it's Download/4Chan, which needs
/// storage access: without it, this explains why in a sheet over
/// [context] (when given and still there) and throws. With [ask] false it
/// only checks for that access, without asking for it.
Future<Directory> requestDirectory({
  BuildContext? context,
  bool ask = true,
}) async {
  if (!Platform.isAndroid) {
    await _ensureThumbnailsDir();
    return getApplicationDocumentsDirectory();
  }

  final int sdkVersion = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
  final permission = sdkVersion >= 30
      ? Permission.manageExternalStorage
      : Permission.storage;

  final bool granted = ask
      ? await permission.request().isGranted
      : await permission.isGranted;
  if (!granted) {
    if (context != null && context.mounted) {
      await showCupertinoModalBottomSheet(
        expand: false,
        context: context,
        builder: (context) => const PermissionDenied(),
      );
    }
    throw const FileSystemException('Storage permission denied');
  }

  final Directory external = (await getExternalStorageDirectory())!;
  String newPath = '';
  for (final String folder in external.path.split('/').skip(1)) {
    if (folder == 'Android') {
      break;
    }
    newPath += '/$folder';
  }
  final Directory directory = Directory('$newPath/Download/4Chan');
  await _ensureThumbnailsDir();

  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }

  return directory;
}

/// Asks to add to Photos or the gallery; it never needs to read them.
Future<bool> _canSaveToGallery() async {
  if (!Platform.isAndroid) {
    return Permission.photosAddOnly.request().isGranted;
  }
  final int sdkVersion = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
  return sdkVersion >= 29 || await Permission.storage.request().isGranted;
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

/// What saving or sharing calls the file it downloads [fileName] into (and
/// so Photos or the share sheet shows): the uploader's name made safe
/// ([_safeBaseName]), or "file" if nothing of it is left.
@visibleForTesting
String localFileName(String fileName) {
  final int dot = fileName.lastIndexOf('.');
  final String ext = dot < 0 ? '' : fileName.substring(dot);
  final String base = _safeBaseName(getNameWithoutExtension(fileName));
  return '${base.isEmpty || base.startsWith('.') ? 'file' : base}$ext';
}

/// What a saved [name] is called on disk: on iOS, webms are kept as mp4s.
String savedNameOnDisk(String name) =>
    Platform.isIOS ? _withMp4Extension(name) : name;

String _withMp4Extension(String name) => name.toLowerCase().endsWith('.webm')
    ? '${name.substring(0, name.length - 5)}.mp4'
    : name;

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
Future<int> _convertWebMToMP4(
  File webmFile,
  File mp4File, {
  void Function(double? progress)? onProgress,
}) async {
  final (int? sourceBitrate, int? durationMs) = await _probe(webmFile);
  final int bitrate = sourceBitrate == null ? 4000000 : 2 * sourceBitrate;

  onProgress?.call(durationMs == null ? null : 0);
  // yuv420p + aac keep the mp4 compatible with the Photos library.
  final FFmpegSession session = await FFmpegKit.executeAsync(
    '-y -i "${webmFile.path}" -vf "crop=trunc(iw/2)*2:trunc(ih/2)*2:0:0" -c:v h264_videotoolbox -allow_sw 1 -b:v $bitrate -pix_fmt yuv420p -c:a aac "${mp4File.path}"',
    onStatistics: onProgress == null || durationMs == null
        ? null
        : (Statistics statistics) =>
              onProgress((statistics.time / durationMs).clamp(0, 1)),
  );

  final int returnCode = session.getReturnCode();
  if (returnCode == 0) {
    // ffmpeg's last report stops a frame or so short of the length.
    onProgress?.call(1);
  }
  return returnCode;
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

/// What saving or sharing [url] gives out: downloaded into [folder] under a
/// safe name and, for a webm on iPhone, converted to an mp4.
Future<File> _downloadToGive(
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
  final int returnCode = await _convertWebMToMP4(
    downloaded,
    mp4,
    onProgress: steps.convert,
  );
  if (returnCode != 0) {
    throw Exception('webm conversion failed');
  }
  await _deleteQuietly(downloaded);
  return mp4;
}

/// Downloads an attachment to Photos/gallery; returns whether it got there.
/// Failures are shown in a snackbar.
Future<bool> saveVideo(
  String url,
  String fileName,
  BuildContext context, {
  SaveProgress? onProgress,
}) async {
  if (!await _canSaveToGallery()) {
    if (context.mounted) {
      _showFailed(context, 'Permission denied');
    }
    return false;
  }

  Directory? work;
  try {
    work = await _newWorkFolder();
    final File file = await _downloadToGive(work, url, fileName, onProgress);
    if (!await _saveToGallery(file.path, file.path.split('/').last)) {
      throw Exception('gallery save failed');
    }
    return true;
  } catch (e) {
    debugPrint('saveVideo error: $e');
    if (context.mounted) {
      _showFailed(context);
    }
    return false;
  } finally {
    if (work != null) {
      await _deleteQuietly(work);
    }
  }
}

/// Saves already-saved attachments to Photos/gallery; returns the number that
/// failed, or null without the permission, which is shown in a snackbar.
Future<int?> saveSavedAttachmentsToGallery(
  List<String> fileNames,
  BuildContext context,
) async {
  if (!await _canSaveToGallery()) {
    if (context.mounted) {
      _showFailed(context, 'Permission denied');
    }
    return null;
  }

  final Directory directory;
  try {
    directory = await requestDirectory();
  } catch (_) {
    return fileNames.length;
  }

  int failed = 0;
  for (final fileName in fileNames) {
    final String savedName = savedNameOnDisk(fileName);
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

/// Opens one share sheet for all given saved attachments (includes "Save to
/// Files"). If none of them can be, that's shown in a snackbar.
Future<void> shareSavedAttachments(
  List<String> fileNames,
  BuildContext context,
) async {
  final Directory directory;
  try {
    directory = await requestDirectory(context: context);
  } catch (_) {
    // The permission sheet said why.
    return;
  }

  try {
    final files = <XFile>[];
    for (final fileName in fileNames) {
      final String savedPath = savedMediaPath(
        directory.path,
        savedNameOnDisk(fileName),
      );
      if (await File(savedPath).exists()) {
        files.add(XFile(savedPath));
      }
    }
    if (files.isEmpty) {
      throw const FileSystemException('Saved files are gone');
    }
    await shareInTurn(ShareParams(files: files));
  } catch (e) {
    debugPrint('shareSavedAttachments error: $e');
    if (context.mounted) {
      _showFailed(context, "Couldn't share it");
    }
  }
}

/// Downloads an attachment and opens the share sheet for it.
Future<void> shareMedia(
  String url,
  String fileName,
  BuildContext context, {
  SaveProgress? onProgress,
}) async {
  Directory? shareFolder;
  bool shared = false;
  try {
    shareFolder = await _newShareFolder();
    final File file = await _downloadToGive(
      shareFolder,
      url,
      fileName,
      onProgress,
    );
    await shareInTurn(ShareParams(files: [XFile(file.path)]));
    shared = true;
  } catch (e) {
    debugPrint('shareMedia error: $e');
    if (context.mounted) {
      _showFailed(context);
    }
  } finally {
    if (shareFolder != null) {
      // What was shared stays until the next share; a failed one goes now.
      finishShareFolder(shareFolder);
      if (!shared) {
        await _deleteQuietly(shareFolder);
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

// Done when the share sheet is free: it shows one share at a time.
Future<void> _shareSheetFree = Future<void>.value();

/// Opens the share sheet for [params] once the shares before it have
/// closed theirs, so shares readied at once open one after another.
@visibleForTesting
Future<void> shareInTurn(ShareParams params) async {
  final Future<void> before = _shareSheetFree;
  final Completer<void> mine = Completer<void>();
  _shareSheetFree = mine.future;
  try {
    await before;
    await showShareSheet(params);
  } finally {
    mine.complete();
  }
}

void _showFailed(
  BuildContext context, [
  String message = 'Download failed :(',
]) {
  showCupertinoSnackbar(
    const Duration(milliseconds: 1800),
    true,
    context,
    message,
  );
}

/// Saves an attachment to the Saved tab; null if it couldn't, which is
/// shown in a snackbar over [context] (or, without storage access, a sheet).
/// A failed save leaves no file behind.
Future<SavedAttachment?> saveAttachment(
  String url,
  String thumbnailUrl,
  String fileName,
  String displayName,
  BuildContext context,
  SavedAttachmentsProvider savedAttachmentsProvider, {
  SaveProgress? onProgress,
}) async {
  final Directory baseDirectory;
  try {
    baseDirectory = await requestDirectory(context: context);
  } catch (_) {
    // The permission sheet said why.
    return null;
  }

  final Directory savedDir = Directory(savedMediaDirPath(baseDirectory.path));
  String? savedName;
  Directory? work;
  File? output;
  try {
    if (!await savedDir.exists()) {
      await savedDir.create(recursive: true);
    }
    final String thumbsDir = await _ensureThumbnailsDir();

    work = await _newWorkFolder();
    final SaveSteps steps = SaveSteps(
      onProgress,
      converts: _converts(fileName),
    );
    final File downloadedFile = await downloadInto(
      work,
      url,
      fileName,
      onProgress: steps.download,
    );
    final String ext = '.${fileName.split('.').last}'.toLowerCase();

    final bool isVideoLike = ext == '.mp4' || ext == '.webm' || ext == '.gif';
    final String targetExt = Platform.isIOS && ext == '.webm' ? '.mp4' : ext;
    savedName =
        await uniqueSavedFileName(
          savedDir.path,
          displayName,
          targetExt,
          reserve: true,
        ) ??
        '${getNameWithoutExtension(fileName)}$targetExt';

    output = File('${savedDir.path}/$savedName');
    if (_converts(fileName)) {
      if (await _convertWebMToMP4(
            downloadedFile,
            output,
            onProgress: steps.convert,
          ) !=
          0) {
        throw Exception('webm conversion failed');
      }
    } else {
      await downloadedFile.copy(output.path);
    }

    final String thumbnailPath = isVideoLike
        ? await _videoThumbnail(output.path, fileName, thumbnailUrl, thumbsDir)
        : savedName;

    final SavedAttachment attachment = SavedAttachment(
      savedAttachmentType: isVideoLike
          ? SavedAttachmentType.video
          : SavedAttachmentType.image,
      fileName: savedName,
      thumbnail: thumbnailPath,
      id: getNameWithoutExtension(fileName),
    );
    output = null;
    return attachment;
  } catch (e, st) {
    debugPrint('saveAttachment error: $e\n$st');
    final File? partial = output;
    if (partial != null) {
      // A half-converted or unlisted file would linger in Files.
      await _deleteQuietly(partial);
    }
    if (context.mounted) {
      _showFailed(context, "Couldn't save it");
    }
    return null;
  } finally {
    if (savedName != null) {
      // Written (and found by name from now on), or deleted.
      releaseSavedFileName(savedDir.path, savedName);
    }
    if (work != null) {
      await _deleteQuietly(work);
    }
  }
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
  final String clipped = _safeBaseName(getNameWithoutExtension(originalName));
  if (clipped.isEmpty || clipped.startsWith('.')) {
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

/// Lets go of a name [uniqueSavedFileName] reserved.
void releaseSavedFileName(String dir, String name) {
  _reservedSavedPaths.remove('$dir/$name');
}

/// Grabs a frame from the video itself; falls back to 4chan's tiny 125px thumb.
Future<String> _videoThumbnail(
  String videoPath,
  String fileName,
  String thumbnailUrl,
  String thumbsDir,
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
  return downloadThumbnail(fileName, thumbnailUrl, '$thumbsDir/');
}

// Saving and sharing download and convert in folders of their own in the
// temporary directory, so they can't overwrite each other's files, and
// what they leave there can be found and deleted.
const String _workingFolderName = 'working';
const String _sharedFolderName = 'shared';

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
Future<Directory> _newWorkFolder() async {
  final Directory temp = await getTemporaryDirectory();
  final Directory working = await Directory(
    '${temp.path}/$_workingFolderName',
  ).create(recursive: true);
  return working.createTemp();
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
    '${temp.path}/$_sharedFolderName',
  ).create(recursive: true);
  // In use from before it exists, so a share starting meanwhile keeps it.
  final Directory folder = Directory(
    '${shared.path}/${DateTime.now().microsecondsSinceEpoch}-'
    '${_shareFolderCount++}',
  );
  _shareFoldersInUse.add(folder.path);
  await for (final FileSystemEntity entity in shared.list()) {
    if (!_shareFoldersInUse.contains(entity.path)) {
      await _deleteQuietly(entity);
    }
  }
  return folder.create();
}

/// [folder]'s share is done: the next share may delete it.
@visibleForTesting
void finishShareFolder(Directory folder) {
  _shareFoldersInUse.remove(folder.path);
}

Future<void> _deleteQuietly(FileSystemEntity entity) async {
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
        ? name == _workingFolderName || name == _sharedFolderName
        : _mediaExtensions.any(name.toLowerCase().endsWith);
    if (isLeftover) {
      await _deleteQuietly(entity);
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

// A connection that sends nothing for this long is given up on, instead of
// leaving the save spinning forever.
const Duration _stallTimeout = Duration(seconds: 20);

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
    final http.StreamedResponse response = await httpClient
        .send(http.Request('GET', uri))
        .timeout(_stallTimeout);
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
        response.stream.timeout(_stallTimeout).map((List<int> chunk) {
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

Future<String> downloadThumbnail(
  String fileName,
  String thumbnailUrl,
  String path,
) async {
  final String nameWithoutExtension = getNameWithoutExtension(fileName);

  await _download(thumbnailUrl, File('$path$nameWithoutExtension.jpg'));

  return '$nameWithoutExtension.jpg';
}

String getNameWithoutExtension(String fileName) {
  if (fileName.contains('.')) {
    return fileName.substring(0, fileName.lastIndexOf('.'));
  } else {
    return fileName;
  }
}
