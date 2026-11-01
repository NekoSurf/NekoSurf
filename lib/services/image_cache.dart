import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

// Images are kept on disk as well as in memory, so ones seen before show
// without downloading them again, also after the app restarts.

const String _thumbnailsKey = 'thumbnail_cache';
const String _imagesKey = 'image_cache';

/// 4chan's thumbnails are a few KB each: many, for two weeks.
final CacheManager _thumbnails = CacheManager(
  Config(
    _thumbnailsKey,
    stalePeriod: const Duration(days: 14),
    maxNrOfCacheObjects: 4000,
  ),
);

/// Full-size images run to a few MB: fewer, and not for as long.
final CacheManager _images = CacheManager(
  Config(
    _imagesKey,
    stalePeriod: const Duration(days: 3),
    maxNrOfCacheObjects: 150,
  ),
);

/// A thumbnail (`<tim>s.jpg`), from the disk cache when it's there.
ImageProvider<Object> thumbnailImage(String url) =>
    CachedNetworkImageProvider(url, cacheManager: _thumbnails);

/// A full-size image, from the disk cache when it's there.
ImageProvider<Object> fullImage(String url) =>
    CachedNetworkImageProvider(url, cacheManager: _images);

/// What cached images take up on disk, in bytes.
Future<int> imageCacheSize() async {
  try {
    final Directory temp = await getTemporaryDirectory();
    int total = 0;
    for (final String key in const [_thumbnailsKey, _imagesKey]) {
      final Directory dir = Directory('${temp.path}/$key');
      if (!dir.existsSync()) {
        continue;
      }
      for (final File file in dir.listSync().whereType<File>()) {
        total += file.lengthSync();
      }
    }
    return total;
  } catch (_) {
    return 0;
  }
}

/// Deletes every cached image from disk.
Future<void> clearImageCache() async {
  await _thumbnails.emptyCache();
  await _images.emptyCache();
}
