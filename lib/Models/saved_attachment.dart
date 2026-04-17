enum SavedAttachmentType { Image, Video }

class SavedAttachment {
  SavedAttachment({this.savedAttachmentType, this.fileName, this.thumbnail});

  factory SavedAttachment.fromJson(Map<String, dynamic> json) {
    final String? fileName = json['fileName'] as String?;

    return SavedAttachment(
      savedAttachmentType: _parseSavedAttachmentType(
        json['savedAttachmentType'],
        fileName,
      ),
      fileName: fileName,
      thumbnail: json['thumbnail'] as String?,
    );
  }

  SavedAttachmentType? savedAttachmentType;
  String? fileName;
  String? thumbnail;

  Map<String, dynamic> toJson() {
    return {
      'savedAttachmentType': savedAttachmentType?.name,
      'fileName': fileName,
      'thumbnail': thumbnail,
    };
  }

  static SavedAttachmentType _parseSavedAttachmentType(
    dynamic value,
    String? fileName,
  ) {
    if (value is int &&
        value >= 0 &&
        value < SavedAttachmentType.values.length) {
      return SavedAttachmentType.values[value];
    }

    if (value is String) {
      final String normalized = value.split('.').last.toLowerCase();

      if (normalized == 'video') {
        return SavedAttachmentType.Video;
      }

      if (normalized == 'image') {
        return SavedAttachmentType.Image;
      }

      try {
        return SavedAttachmentType.values.byName(value);
      } catch (_) {
        // Fallback is handled below.
      }
    }

    final String ext = fileName != null && fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';

    return ext == 'mp4' || ext == 'webm' || ext == 'gif'
        ? SavedAttachmentType.Video
        : SavedAttachmentType.Image;
  }
}
