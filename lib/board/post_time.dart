import 'package:flutter_chan/chan/post.dart';
import 'package:intl/intl.dart';

String formatPostedAt(Post post) {
  final DateTime? postedAt = post.postedAt;
  return postedAt == null ? '' : DateFormat('kk:mm - dd.MM.y').format(postedAt);
}
