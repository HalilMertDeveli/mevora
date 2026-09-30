import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

/// Fetches the bytes behind [uri]. Replaced in tests.
typedef ImageBytesFetcher = Future<Uint8List> Function(Uri uri);

/// Bounded on-disk cache for immutable photo URLs.
///
/// Flutter's own image cache is memory-only (see ImageCachePolicy), so every
/// cold start re-downloaded every profile photo. Published photo URLs never
/// change their bytes — a new upload gets a new imageId and a new token — so a
/// URL is a safe cache key and an entry never needs revalidating.
///
/// Bounded two ways: total size ([maxBytes], least-recently-used evicted
/// first) and idle age ([maxIdle]). Every disk failure degrades to a plain
/// network fetch; the cache can never be the reason a photo does not load.
class ImageDiskCache {
  ImageDiskCache({
    required Future<Directory> Function() directory,
    ImageBytesFetcher? fetcher,
    this.maxBytes = 100 * 1024 * 1024,
    this.maxEntryBytes = 8 * 1024 * 1024,
    this.maxIdle = const Duration(days: 30),
    DateTime Function()? clock,
  }) : _directory = directory,
       _fetcher = fetcher ?? _httpFetch,
       _clock = clock ?? DateTime.now;

  /// The app-wide cache, under the platform cache directory (the OS may also
  /// clear it under storage pressure, which is fine for a cache).
  static final ImageDiskCache instance = ImageDiskCache(
    directory: () async => Directory(
      '${(await getApplicationCacheDirectory()).path}/mevora_images',
    ),
  );

  final Future<Directory> Function() _directory;
  final ImageBytesFetcher _fetcher;
  final DateTime Function() _clock;

  final int maxBytes;
  final int maxEntryBytes;
  final Duration maxIdle;

  Future<Directory?>? _dir;
  final Map<String, Future<Uint8List>> _inFlight = {};
  int _bytesSinceTrim = 0;
  bool _trimmedThisRun = false;

  /// Disk hits, network fetches — for tests and the bandwidth measurement.
  int hits = 0;
  int fetches = 0;

  /// Returns the bytes for [url] from disk, or fetches and stores them.
  /// Concurrent requests for one URL share a single download.
  Future<Uint8List> load(String url) {
    final pending = _inFlight[url];
    if (pending != null) {
      return pending;
    }
    // Block body: an arrow returning the removed future would make this
    // future wait on itself.
    final future = _load(url).whenComplete(() {
      unawaited(_inFlight.remove(url));
    });
    _inFlight[url] = future;
    return future;
  }

  Future<Uint8List> _load(String url) async {
    final dir = await _resolveDir();
    final file = dir == null ? null : File('${dir.path}/${keyFor(url)}');
    if (file != null) {
      final cached = await _read(file);
      if (cached != null) {
        hits++;
        return cached;
      }
    }
    fetches++;
    final bytes = await _fetcher(Uri.parse(url));
    if (file != null && bytes.isNotEmpty && bytes.length <= maxEntryBytes) {
      await _write(file, bytes);
    }
    return bytes;
  }

  /// Stable file name for [url]. Exposed for tests.
  static String keyFor(String url) => sha256.convert(url.codeUnits).toString();

  Future<Directory?> _resolveDir() {
    return _dir ??= () async {
      try {
        final dir = await _directory();
        await dir.create(recursive: true);
        return dir;
      } on Object {
        // No platform cache directory (widget tests, a sandbox quirk):
        // behave as a plain network image.
        return null;
      }
    }();
  }

  Future<Uint8List?> _read(File file) async {
    try {
      if (!await file.exists()) {
        return null;
      }
      final now = _clock();
      final modified = await file.lastModified();
      if (now.difference(modified) > maxIdle) {
        await file.delete();
        return null;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        return null;
      }
      // lastModified doubles as last-used, so eviction is least-recently-used.
      unawaited(file.setLastModified(now).catchError((Object _) {}));
      return bytes;
    } on Object {
      return null;
    }
  }

  Future<void> _write(File file, Uint8List bytes) async {
    try {
      // Write-then-rename so a crash mid-write never leaves a truncated
      // entry that later decodes as a broken photo.
      final part = File('${file.path}.part');
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(file.path);
      _bytesSinceTrim += bytes.length;
      if (!_trimmedThisRun || _bytesSinceTrim > maxBytes ~/ 10) {
        unawaited(trim());
      }
    } on Object {
      // Disk full or read-only: skip caching this one.
    }
  }

  /// Evicts least-recently-used entries until the cache is under 90% of
  /// [maxBytes], and drops anything idle longer than [maxIdle].
  Future<void> trim() async {
    _trimmedThisRun = true;
    _bytesSinceTrim = 0;
    final dir = await _resolveDir();
    if (dir == null) {
      return;
    }
    try {
      final entries = <(File, int, DateTime)>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        final stat = await entity.stat();
        entries.add((entity, stat.size, stat.modified));
      }
      final now = _clock();
      var total = 0;
      final live = <(File, int, DateTime)>[];
      for (final entry in entries) {
        if (now.difference(entry.$3) > maxIdle) {
          await _deleteQuietly(entry.$1);
        } else {
          live.add(entry);
          total += entry.$2;
        }
      }
      final target = (maxBytes * 0.9).floor();
      if (total <= maxBytes) {
        return;
      }
      live.sort((a, b) => a.$3.compareTo(b.$3));
      for (final entry in live) {
        if (total <= target) {
          break;
        }
        await _deleteQuietly(entry.$1);
        total -= entry.$2;
      }
    } on Object {
      // Best effort; the next write tries again.
    }
  }

  /// Drops every cached photo. Called on sign-out so the next account on this
  /// device does not inherit the previous member's viewing history.
  Future<void> clear() async {
    final dir = await _resolveDir();
    if (dir == null) {
      return;
    }
    try {
      await for (final entity in dir.list(followLinks: false)) {
        await _deleteQuietly(entity);
      }
    } on Object {
      // Best effort.
    }
  }

  static Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      await entity.delete();
    } on Object {
      // Already gone or locked.
    }
  }

  static HttpClient? _client;

  static Future<Uint8List> _httpFetch(Uri uri) async {
    final client = _client ??= HttpClient()..autoUncompress = false;
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<List<int>>(<int>[]);
      throw NetworkImageLoadException(
        statusCode: response.statusCode,
        uri: uri,
      );
    }
    final bytes = await consolidateHttpClientResponseBytes(response);
    if (bytes.lengthInBytes == 0) {
      throw Exception('Empty image response: $uri');
    }
    return bytes;
  }
}

/// [NetworkImage] with [ImageDiskCache] underneath: same decoding, but the
/// bytes survive an app restart.
@immutable
class DiskCachedNetworkImage extends ImageProvider<DiskCachedNetworkImage> {
  const DiskCachedNetworkImage(this.url, {this.scale = 1.0, this.cache});

  final String url;
  final double scale;

  /// Defaults to [ImageDiskCache.instance].
  final ImageDiskCache? cache;

  @override
  Future<DiskCachedNetworkImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<DiskCachedNetworkImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    DiskCachedNetworkImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: key.scale,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<DiskCachedNetworkImage>('Image key', key),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
    DiskCachedNetworkImage key,
    ImageDecoderCallback decode,
  ) async {
    try {
      final bytes = await (cache ?? ImageDiskCache.instance).load(key.url);
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return decode(buffer);
    } on Object {
      // Same as NetworkImage: a failed load must not stay in the memory
      // cache, or a retry would replay the failure.
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is DiskCachedNetworkImage &&
        other.url == url &&
        other.scale == scale;
  }

  @override
  int get hashCode => Object.hash(url, scale);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'DiskCachedNetworkImage')}("$url", scale: ${scale.toStringAsFixed(1)})';
}
