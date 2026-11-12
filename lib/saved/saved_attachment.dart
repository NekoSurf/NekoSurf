import 'dart:convert';

enum SavedAttachmentType { image, video }

String getNameWithoutExtension(String fileName) {
  final int dot = fileName.lastIndexOf('.');
  return dot < 0 ? fileName : fileName.substring(0, dot);
}

/// Whether a file of this name is listed as a video: gifs are, with their
/// thumbnail apart from them.
bool isVideoFileName(String fileName) {
  final String lower = fileName.toLowerCase();
  return lower.endsWith('.mp4') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.gif');
}

class SavedAttachment {
  SavedAttachment({
    required this.type,
    required this.fileName,
    required this.thumbnail,
    this.originalName,
    String? id,
    this.addedAt,
  }) : _id = id;

  /// What's stored for it. Older versions stored just the file name, or
  /// numbered the type; null if it's corrupt.
  static SavedAttachment? fromStored(String stored) {
    final String value = stored.trim();
    if (value.isEmpty) {
      return null;
    }
    if (!value.startsWith('{')) {
      return SavedAttachment(
        type: _typeFromName(value),
        fileName: value,
        thumbnail: isVideoFileName(value)
            ? '${getNameWithoutExtension(value)}.jpg'
            : value,
      );
    }
    try {
      final Map<String, dynamic> json =
          jsonDecode(value) as Map<String, dynamic>;
      // Older versions could store a path.
      final String fileName = (json['fileName'] as String).split('/').last;
      return SavedAttachment(
        type: _parseType(json['savedAttachmentType'], fileName),
        fileName: fileName,
        thumbnail: json['thumbnail'] as String? ?? fileName,
        originalName: json['originalName'] as String?,
        id: json['id'] as String?,
        addedAt: (json['addedAt'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  final SavedAttachmentType type;

  /// The unique on-disk name; it follows the uploader's.
  final String fileName;

  /// [fileName] for an image, which is its own thumbnail.
  final String thumbnail;

  /// Older versions kept the uploader's filename here, to rename files named
  /// after their upload to (saved_migrations.dart).
  final String? originalName;

  final String? _id;

  /// When it was saved (milliseconds since 1970), on whichever device;
  /// null if before that was kept.
  final int? addedAt;

  /// Where it goes in the list, the same on every device: when it was
  /// saved, or, from before that was kept, when its post was made (an
  /// upload's `tim` is that time).
  int get sortTime {
    if (addedAt case final int added) {
      return added;
    }
    int tim = int.tryParse(id) ?? 0;
    // Microseconds on some boards.
    while (tim > 100000000000000) {
      tim ~/= 1000;
    }
    return tim;
  }

  bool get isVideo => type == SavedAttachmentType.video;

  bool get hasOwnThumbnail => thumbnail != fileName;

  /// The 4chan upload (`tim`) it's of. Older entries have no id of their own,
  /// and were stored under it as their file name.
  String get id => _id ?? getNameWithoutExtension(fileName);

  /// It's from before files were named after the uploader's.
  bool get isNamedAfterUpload => _id == null;

  SavedAttachment renamedTo(String newName) => SavedAttachment(
    type: type,
    fileName: newName,
    thumbnail: thumbnail == fileName ? newName : thumbnail,
    originalName: originalName,
    id: id,
    addedAt: addedAt,
  );

  /// It, saved at [time].
  SavedAttachment addedAtTime(DateTime time) =>
      withAddedAt(time.millisecondsSinceEpoch);

  /// It, saved at [addedAt]; with none if that's null.
  SavedAttachment withAddedAt(int? addedAt) => SavedAttachment(
    type: type,
    fileName: fileName,
    thumbnail: thumbnail,
    originalName: originalName,
    id: _id,
    addedAt: addedAt,
  );

  SavedAttachment withStoredId() => SavedAttachment(
    type: type,
    fileName: fileName,
    thumbnail: thumbnail,
    originalName: originalName,
    id: id,
    addedAt: addedAt,
  );

  Map<String, dynamic> toJson() {
    return {
      'savedAttachmentType': type.name,
      'fileName': fileName,
      'thumbnail': thumbnail,
      'originalName': originalName,
      'id': _id,
      if (addedAt != null) 'addedAt': addedAt,
    };
  }

  static SavedAttachmentType _typeFromName(String fileName) =>
      isVideoFileName(fileName)
      ? SavedAttachmentType.video
      : SavedAttachmentType.image;

  static SavedAttachmentType _parseType(dynamic value, String fileName) {
    if (value is int &&
        value >= 0 &&
        value < SavedAttachmentType.values.length) {
      return SavedAttachmentType.values[value];
    }
    if (value is String) {
      final String normalized = value.split('.').last.toLowerCase();
      for (final SavedAttachmentType type in SavedAttachmentType.values) {
        if (type.name == normalized) {
          return type;
        }
      }
    }
    return _typeFromName(fileName);
  }
}
