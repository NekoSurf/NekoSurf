import 'package:flutter_cache_manager/flutter_cache_manager.dart';

Future<String> resolveCachedVideoSource(String source) async {
  final uri = Uri.tryParse(source);
  final isNetwork =
      uri != null && (uri.scheme == 'http' || uri.scheme == 'https');

  if (!isNetwork) {
    return source;
  }

  final cacheManager = DefaultCacheManager();
  final cached = await cacheManager.getFileFromCache(source);
  if (cached != null) {
    return Uri.file(cached.file.path).toString();
  }

  // Do not block playback on a full download.
  return source;
}
