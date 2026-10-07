import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Like [NetworkImage], but persists the downloaded bytes in the
/// [DefaultCacheManager] disk cache so images survive app restarts.
@immutable
class CachedNetworkImageProvider
    extends ImageProvider<CachedNetworkImageProvider> {
  const CachedNetworkImageProvider(this.url, {this.scale = 1.0});

  final String url;
  final double scale;

  @override
  Future<CachedNetworkImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) {
    return SynchronousFuture<CachedNetworkImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    CachedNetworkImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final StreamController<ImageChunkEvent> chunkEvents =
        StreamController<ImageChunkEvent>();

    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode, chunkEvents),
      chunkEvents: chunkEvents.stream,
      scale: key.scale,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<CachedNetworkImageProvider>('Image key', key),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
    CachedNetworkImageProvider key,
    ImageDecoderCallback decode,
    StreamController<ImageChunkEvent> chunkEvents,
  ) async {
    try {
      await for (final FileResponse response
          in DefaultCacheManager().getFileStream(key.url, withProgress: true)) {
        if (response is DownloadProgress) {
          chunkEvents.add(
            ImageChunkEvent(
              cumulativeBytesLoaded: response.downloaded,
              expectedTotalBytes: response.totalSize,
            ),
          );
        } else if (response is FileInfo) {
          final Uint8List bytes = await response.file.readAsBytes();
          if (bytes.isEmpty) {
            throw StateError('$url is an empty file.');
          }

          final ui.ImmutableBuffer buffer =
              await ui.ImmutableBuffer.fromUint8List(bytes);
          return decode(buffer);
        }
      }

      throw StateError('Failed to load $url.');
    } catch (_) {
      // Let a later attempt retry instead of reusing the failed completer.
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      rethrow;
    } finally {
      unawaited(chunkEvents.close());
    }
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is CachedNetworkImageProvider &&
        other.url == url &&
        other.scale == scale;
  }

  @override
  int get hashCode => Object.hash(url, scale);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'CachedNetworkImageProvider')}("$url", scale: ${scale.toStringAsFixed(1)})';
}
