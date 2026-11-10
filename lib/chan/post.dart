import 'package:flutter_chan/chan/post_text.dart';
import 'package:flutter_chan/chan/urls.dart' as urls;

class Post {
  Post({
    required this.board,
    required this.no,
    this.sticky,
    this.closed,
    this.name,
    this.sub,
    this.com,
    this.filename,
    this.ext,
    this.w,
    this.h,
    this.tnW,
    this.tnH,
    this.tim,
    this.time,
    this.resto,
    this.replies,
    this.images,
    this.lastModified,
    this.country,
    this.countryName,
    this.archived,
    this.id,
    this.trip,
    this.capcode,
    this.spoiler,
  });

  /// A post of [board], as 4chan's API describes it.
  factory Post.fromJson(Map<String, dynamic> json, String board) => Post(
    no: json['no'] as int,
    sticky: json['sticky'] as int?,
    closed: json['closed'] as int?,
    name: json['name'] as String?,
    sub: json['sub'] as String?,
    com: json['com'] as String?,
    filename: json['filename'] as String?,
    ext: json['ext'] as String?,
    w: json['w'] as int?,
    h: json['h'] as int?,
    tnW: json['tn_w'] as int?,
    tnH: json['tn_h'] as int?,
    tim: json['tim'] as int?,
    time: json['time'] as int?,
    resto: json['resto'] as int?,
    replies: json['replies'] as int?,
    images: json['images'] as int?,
    lastModified: json['last_modified'] as int?,
    country: json['country'] as String?,
    countryName: json['country_name'] as String?,
    board: board,
    archived: json['archived'] as int?,
    id: json['id'] as String?,
    trip: json['trip'] as String?,
    capcode: json['capcode'] as String?,
    spoiler: json['spoiler'] as int?,
  );

  /// A thread's opening post as it's remembered (bookmarks, history), which
  /// is enough to show it until it's loaded.
  factory Post.remembered({
    required String board,
    required int no,
    String? sub,
    String? com,
    String? thumbnailName,
  }) => Post(
    board: board,
    no: no,
    sub: sub,
    com: com,
    tim: thumbnailName != null && thumbnailName.endsWith(_thumbnailSuffix)
        ? int.tryParse(
            thumbnailName.substring(
              0,
              thumbnailName.length - _thumbnailSuffix.length,
            ),
          )
        : null,
  );

  static const String _thumbnailSuffix = 's.jpg';

  final String board;
  final int no;
  final int? sticky;
  final int? closed;
  final String? name;
  final String? sub;
  final String? com;
  final String? filename;
  final String? ext;
  final int? w;
  final int? h;
  final int? tnW;
  final int? tnH;
  final int? tim;
  final int? time;
  final int? resto;
  final int? replies;
  final int? images;
  final int? lastModified;
  final String? country;

  /// The name of [country], like "France".
  final String? countryName;
  final int? archived;

  /// The poster's ID in this thread, on boards that show them.
  final String? id;
  final String? trip;

  /// The staff role the post is by, like "mod".
  final String? capcode;
  final int? spoiler;

  /// The upload ([tim]) if it's a spoiler, to cover it (see SpoilerCover).
  int? get spoilerUpload => spoiler == 1 ? tim : null;

  /// The name of its thumbnail, to keep showing it later; a spoiler has none.
  String? get thumbnailName =>
      tim == null || spoiler == 1 ? null : '$tim$_thumbnailSuffix';

  /// The attached file's address; see [hasFile].
  String get fileUrl => urls.file(board, tim, ext);

  /// The small JPEG of the attached file, videos included; see [hasFile].
  String get thumbnailUrl => urls.thumbnail(board, tim);

  /// What 4chan calls the attached file: `tim` is unique per upload.
  String get uploadName => '$tim$ext';

  String get posterFileName => '$filename$ext';

  String get uploadId => '$tim';

  String? get subject {
    final String? text = sub == null ? null : plainText(sub!).trim();
    return text == null || text.isEmpty ? null : text;
  }

  String get commentText => plainText(com ?? '').trim();

  String get posterName {
    final String text = plainText(name ?? '').trim();
    return text.isEmpty ? 'Anonymous' : text;
  }

  /// When it was posted; null if that isn't known.
  DateTime? get postedAt =>
      time == null ? null : DateTime.fromMillisecondsSinceEpoch(time! * 1000);

  String get title => subject ?? commentText;

  bool get isSticky => sticky == 1;

  bool get hasFile => tim != null && ext != null;

  /// Whether the attached file is a video; 4chan takes webm and mp4.
  bool get isVideo {
    final String? lower = ext?.toLowerCase();
    return lower == '.webm' || lower == '.mp4';
  }
}
