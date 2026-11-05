class Post {
  Post({
    this.no,
    this.sticky,
    this.closed,
    this.now,
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
    this.board,
    this.archived,
    this.spoiler,
  });

  factory Post.fromJson(Map<String?, dynamic> json) => Post(
    no: json['no'] as int?,
    sticky: json['sticky'] as int?,
    closed: json['closed'] as int?,
    now: json['now'] as String?,
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
    board: json['board'] as String?,
    archived: json['archived'] as int?,
    spoiler: json['spoiler'] as int?,
  );

  int? no;
  int? sticky;
  int? closed;
  String? now;
  String? name;
  String? sub;
  String? com;
  String? filename;
  String? ext;
  int? w;
  int? h;
  int? tnW;
  int? tnH;
  int? tim;
  int? time;
  int? resto;
  int? replies;
  int? images;
  int? lastModified;
  String? country;
  String? board;
  int? archived;

  int? spoiler;

  /// The upload ([tim]) if it's a spoiler, to cover it (see SpoilerCover).
  int? get spoilerUpload => spoiler == 1 ? tim : null;

  /// The name of its thumbnail, to keep showing it later; a spoiler has none.
  String? get thumbnailName =>
      tim == null || spoiler == 1 ? null : '${tim}s.jpg';

  /// Whether a file is attached ([tim] and [ext] are set).
  bool get hasFile => tim != null && ext != null;

  /// Whether the attached file is a video; 4chan takes webm and mp4.
  bool get isVideo {
    final String? lower = ext?.toLowerCase();
    return lower == '.webm' || lower == '.mp4';
  }

  Map<String, dynamic> toJson() => {
    'no': no,
    'sticky': sticky,
    'closed': closed,
    'now': now,
    'name': name,
    'sub': sub,
    'com': com,
    'filename': filename,
    'ext': ext,
    'w': w,
    'h': h,
    'tn_w': tnW,
    'tn_h': tnH,
    'tim': tim,
    'time': time,
    'resto': resto,
    'replies': replies,
    'images': images,
    'board': board,
    'archived': archived,
    'spoiler': spoiler,
  };
}
