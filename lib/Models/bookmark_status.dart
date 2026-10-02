import 'package:flutter_chan/enums/enums.dart';

class BookmarkStatus {
  BookmarkStatus({this.status, this.replies});

  ThreadStatus? status;
  ThreadReplyCount? replies;
}

class ThreadReplyCount {
  ThreadReplyCount({this.replies, this.images});

  int? replies;
  int? images;
}
