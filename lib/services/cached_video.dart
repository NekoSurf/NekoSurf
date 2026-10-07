import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:media_kit/media_kit.dart';

const String _sourceExtraKey = 'source';

final Map<String, Future<File>> _inFlightDownloads = <String, Future<File>>{};

/// Returns a local file URI for [source], downloading it into the disk cache
/// first if needed. Concurrent calls for the same URL share one download.
/// Falls back to the network URL if the download fails.
Future<String> resolveCachedVideoSource(String source) async {
  final uri = Uri.tryParse(source);
  final isNetwork =
      uri != null && (uri.scheme == 'http' || uri.scheme == 'https');

  if (!isNetwork) {
    return source;
  }

  try {
    final File file = await (_inFlightDownloads[source] ??=
        DefaultCacheManager()
            .getSingleFile(source)
            .whenComplete(() => _inFlightDownloads.remove(source)));
    return Uri.file(file.path).toString();
  } catch (_) {
    return source;
  }
}

/// A [Media] for [resolvedSource] that remembers the original [source] URL,
/// so players can be matched to their item even when playing a cached file.
Media cachedMedia(String source, String resolvedSource) {
  return Media(
    resolvedSource,
    extras: <String, dynamic>{_sourceExtraKey: source},
  );
}

/// Whether [player] currently has the media for [source] open.
bool playerHasSource(Player player, String source) {
  final Playlist playlist = player.state.playlist;
  final int index = playlist.index;
  if (index < 0 || index >= playlist.medias.length) {
    return false;
  }

  final Media media = playlist.medias[index];
  return media.uri == source || media.extras?[_sourceExtraKey] == source;
}
