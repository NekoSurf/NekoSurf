import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

Future<String> resolveCachedVideoSource(String source) async {
  final uri = Uri.tryParse(source);
  final isNetwork =
      uri != null && (uri.scheme == 'http' || uri.scheme == 'https');

  if (!isNetwork) {
    return source;
  }

  final File cachedFile = await DefaultCacheManager().getSingleFile(source);
  return Uri.file(cachedFile.path).toString();
}
