import 'package:flutter/foundation.dart';

class WatchedMedia {
  WatchedMedia({
    required this.mediaId,
    required this.board,
    required this.fileName,
    required this.ext,
    required this.watchedAt,
  });

  final int mediaId;
  final String board;
  final String fileName;
  final String ext;
  final DateTime watchedAt;

  Map<String, dynamic> toJson() {
    return {
      'mediaId': mediaId,
      'board': board,
      'fileName': fileName,
      'ext': ext,
      'watchedAt': watchedAt.toIso8601String(),
    };
  }

  factory WatchedMedia.fromJson(Map<String, dynamic> json) {
    return WatchedMedia(
      mediaId: json['mediaId'] as int,
      board: json['board'] as String,
      fileName: json['fileName'] as String,
      ext: json['ext'] as String,
      watchedAt: DateTime.parse(json['watchedAt'] as String),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WatchedMedia &&
        other.mediaId == mediaId &&
        other.board == board;
  }
}
