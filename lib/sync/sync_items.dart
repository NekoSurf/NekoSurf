import 'dart:convert';

import 'package:crypto/crypto.dart';

/// What iCloud sync keeps the same across devices, one record per item.
enum SyncKind {
  setting,
  threadFilter,
  postFilter,
  board,
  bookmark,
  history,

  /// What's remembered about a thread: seen posts, where you left off,
  /// folds and hidden posts.
  threadMemory,
  saved,
}

/// The record [key] of [kind] is kept in: readable, so a deletion says what
/// it's of, unless the key is too long for a record's name.
String syncId(SyncKind kind, String key) {
  final String encoded = base64Url.encode(utf8.encode(key)).replaceAll('=', '');
  return encoded.length <= 200
      ? '${kind.name}.$encoded'
      : '${kind.name}:${sha256.convert(utf8.encode(key))}';
}

/// The kind of the record [id], if it's one of [syncId]'s.
SyncKind? syncKindOf(String id) {
  final String name = id.split(RegExp('[.:]')).first;
  return SyncKind.values
      .where((SyncKind kind) => kind.name == name)
      .firstOrNull;
}

/// The key the record [id] is of; null if only its hash is in it.
String? syncKeyOf(String id) {
  final int dot = id.indexOf('.');
  if (dot < 0) {
    return null;
  }
  final String encoded = id.substring(dot + 1);
  try {
    return utf8.decode(
      base64Url.decode(encoded.padRight((encoded.length + 3) ~/ 4 * 4, '=')),
    );
  } on FormatException {
    return null;
  }
}

/// One thing kept in sync, as it is on this device.
class SyncItem {
  SyncItem(
    this.kind,
    this.key,
    this.data, {
    DateTime? modifiedAt,
    this.media,
    this.thumbnail,
  }) : modifiedAt = modifiedAt ?? DateTime.now();

  final SyncKind kind;
  final String key;
  final Map<String, Object?> data;
  final DateTime modifiedAt;

  /// The saved file's path, for a saved item, and its thumbnail's if it has
  /// one of its own.
  final String? media;
  final String? thumbnail;

  String get id => syncId(kind, key);

  Map<String, Object?> toChannel() => {
    'id': id,
    'kind': kind.name,
    'key': key,
    'data': jsonEncode(data),
    'modifiedAt': modifiedAt.millisecondsSinceEpoch,
    'media': media,
    'thumbnail': thumbnail,
  };
}

/// A change to one thing, made on another device.
class SyncChange {
  SyncChange({
    required this.id,
    required this.kind,
    this.key,
    this.data = const {},
    this.modifiedAt,
    this.media,
    this.thumbnail,
    this.deleted = false,
  });

  /// One that came in from iCloud; null if it's not one of [SyncKind]'s.
  static SyncChange? fromChannel(Map<Object?, Object?> map) {
    final String? id = map['id'] as String?;
    final SyncKind? kind = id == null ? null : syncKindOf(id);
    if (id == null || kind == null) {
      return null;
    }
    Map<String, Object?> data = const {};
    try {
      final Object? decoded = jsonDecode(map['data'] as String? ?? '{}');
      if (decoded is Map<String, Object?>) {
        data = decoded;
      }
    } on FormatException {
      // Taken as empty: nothing of it is applied.
    }
    final num? modifiedAt = map['modifiedAt'] as num?;
    return SyncChange(
      id: id,
      kind: kind,
      key: map['key'] as String? ?? syncKeyOf(id),
      data: data,
      modifiedAt: modifiedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(modifiedAt.toInt()),
      media: map['media'] as String?,
      thumbnail: map['thumbnail'] as String?,
      deleted: map['deleted'] == true,
    );
  }

  final String id;
  final SyncKind kind;
  final String? key;
  final Map<String, Object?> data;
  final DateTime? modifiedAt;
  final String? media;
  final String? thumbnail;
  final bool deleted;

  /// Whether it's about [key] of its kind.
  bool isFor(String key) => id == syncId(kind, key);
}
