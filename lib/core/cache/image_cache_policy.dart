import 'package:flutter/painting.dart';

/// Caps Flutter's image cache so discovery/profile photos stay snappy
/// without unbounded memory growth.
abstract final class ImageCachePolicy {
  static void apply({
    int maximumSize = 80,
    int maximumSizeBytes = 32 * 1024 * 1024,
  }) {
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSize = maximumSize;
    cache.maximumSizeBytes = maximumSizeBytes;
  }
}
