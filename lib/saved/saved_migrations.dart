import 'dart:io';

import 'package:flutter_chan/saved/saved_attachment.dart';
import 'package:flutter_chan/saved/saved_folders.dart';

/// [attachments] with what older versions left behind brought up to date:
/// thumbnails (and, on iOS, media) move out of the old `savedAttachments/`
/// layout, and files named after their upload take the uploader's name.
Future<List<SavedAttachment>> migrateSavedFiles(
  SavedFolders folders,
  List<SavedAttachment> attachments,
) async {
  await _moveOutOfOldLayout(folders, attachments);
  return <SavedAttachment>[
    for (final SavedAttachment attachment in attachments)
      await _withUploadersName(folders, attachment),
  ];
}

Future<void> _moveOutOfOldLayout(
  SavedFolders folders,
  List<SavedAttachment> attachments,
) async {
  // On Android it's still where media lives.
  final Directory old = Directory(
    Platform.isIOS ? '${folders.media}/savedAttachments' : folders.media,
  );
  if (!await old.exists()) {
    return;
  }

  Future<void> move(File source, String target) async {
    if (source.path == target ||
        !await source.exists() ||
        await File(target).exists()) {
      return;
    }
    try {
      await source.rename(target);
    } catch (_) {
      await source.copy(target);
      await source.delete();
    }
  }

  for (final SavedAttachment attachment in attachments) {
    await move(
      File('${old.path}/${attachment.fileName}'),
      folders.mediaPath(attachment),
    );
    if (attachment.hasOwnThumbnail) {
      await move(
        File('${old.path}/${attachment.thumbnail}'),
        folders.thumbnailPath(attachment),
      );
    }
  }

  if (old.path != folders.media && await old.list().isEmpty) {
    await old.delete();
  }
}

Future<SavedAttachment> _withUploadersName(
  SavedFolders folders,
  SavedAttachment attachment,
) async {
  final String? original = attachment.originalName;
  if (!attachment.isNamedAfterUpload || original == null || original.isEmpty) {
    return attachment;
  }
  final String name = attachment.fileName;
  final File file = File(folders.pathOfFile(name));
  if (!await file.exists()) {
    return attachment.withStoredId();
  }
  final String ext = name.contains('.')
      ? '.${name.split('.').last.toLowerCase()}'
      : '';
  final String? target = await uniqueSavedFileName(
    folders.media,
    original,
    ext,
  );
  if (target == null || target == name) {
    return attachment.withStoredId();
  }
  try {
    await file.rename(folders.pathOfFile(target));
  } catch (_) {
    return attachment.withStoredId();
  }
  return attachment.renamedTo(target);
}
