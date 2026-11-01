enum SavedAttachmentType { image, video }

class SavedAttachment {
  SavedAttachment({
    this.savedAttachmentType,
    this.fileName,
    this.thumbnail,
    this.originalName,
    this.id,
  });

  factory SavedAttachment.fromJson(Map<String, dynamic> json) {
    final String? fileName = json['fileName'] as String?;

    return SavedAttachment(
      savedAttachmentType: _parseSavedAttachmentType(
        json['savedAttachmentType'],
        fileName,
      ),
      fileName: fileName,
      thumbnail: json['thumbnail'] as String?,
      originalName: json['originalName'] as String?,
      id: json['id'] as String?,
    );
  }

  SavedAttachmentType? savedAttachmentType;
  String? fileName;
  String? thumbnail;
  // Uploader's filename, for display only; `fileName` is the unique on-disk name.
  String? originalName;
  // 4chan upload id (`tim`); stable key even though `fileName` follows the uploader's name.
  String? id;

  Map<String, dynamic> toJson() {
    return {
      'savedAttachmentType': savedAttachmentType?.name,
      'fileName': fileName,
      'thumbnail': thumbnail,
      'originalName': originalName,
      'id': id,
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
        return SavedAttachmentType.video;
      }

      if (normalized == 'image') {
        return SavedAttachmentType.image;
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
        ? SavedAttachmentType.video
        : SavedAttachmentType.image;
  }
}
