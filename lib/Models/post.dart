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
    this.md5,
    this.fsize,
    this.resto,
    this.capcode,
    this.semanticUrl,
    this.replies,
    this.images,
    this.uniqueIps,
    this.lastModified,
    this.country,
    this.board,
    this.archived,
    this.repliedPosts,
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
    md5: json['md5'] as String?,
    fsize: json['fsize'] as int?,
    resto: json['resto'] as int?,
    capcode: json['capcode'] as String?,
    semanticUrl: json['semantic_url'] as String?,
    replies: json['replies'] as int?,
    images: json['images'] as int?,
    uniqueIps: json['unique_ips'] as int?,
    lastModified: json['last_modified'] as int?,
    country: json['country'] as String?,
    board: json['board'] as String?,
    archived: json['archived'] as int?,
    repliedPosts: json['repliedPosts'] as List<Post>?,
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
  String? md5;
  int? fsize;
  int? resto;
  String? capcode;
  String? semanticUrl;
  int? replies;
  int? images;
  int? uniqueIps;
  int? lastModified;
  String? country;
  String? board;
  int? archived;
  List<Post>? repliedPosts;

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
    'md5': md5,
    'fsize': fsize,
    'resto': resto,
    'capcode': capcode,
    'semantic_url': semanticUrl,
    'replies': replies,
    'images': images,
    'unique_ips': uniqueIps,
    'board': board,
    'archived': archived,
    'repliedPosts': repliedPosts,
  };
}
