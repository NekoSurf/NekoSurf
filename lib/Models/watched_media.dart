class WatchedMedia {
  WatchedMedia({
    required this.mediaId,
    required this.thread,
    required this.fileName,
    required this.ext,
    required this.watchedAt,
  });

  factory WatchedMedia.fromJson(Map<String, dynamic> json) {
    return WatchedMedia(
      mediaId: json['mediaId'] as int,
      thread: json['thread'] as int,
      fileName: json['fileName'] as String,
      ext: json['ext'] as String,
      watchedAt: DateTime.parse(json['watchedAt'] as String),
    );
  }

  final int mediaId;
  final int thread;
  final String fileName;
  final String ext;
  final DateTime watchedAt;

  Map<String, dynamic> toJson() {
    return {
      'mediaId': mediaId,
      'thread': thread,
      'fileName': fileName,
      'ext': ext,
      'watchedAt': watchedAt.toIso8601String(),
    };
  }
}
