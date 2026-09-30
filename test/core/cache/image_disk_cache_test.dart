import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/cache/image_disk_cache.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';

const _storageUrl =
    'https://firebasestorage.googleapis.com/v0/b/mevora.appspot.com/o/'
    'users%2Fu1%2Fprofile%2Fthumbs%2Fimg1_card.jpg?alt=media&token=t1';

Uint8List _bytes(int length, [int fill = 7]) =>
    Uint8List.fromList(List<int>.filled(length, fill));

void main() {
  late Directory dir;
  late int fetches;
  late DateTime now;

  Future<Uint8List> fetcher(Uri uri) async {
    fetches++;
    return _bytes(1000, uri.toString().length % 250);
  }

  ImageDiskCache cache({
    int maxBytes = 100 * 1024,
    ImageBytesFetcher? fetch,
    Future<Directory> Function()? directory,
  }) => ImageDiskCache(
    directory: directory ?? () async => dir,
    fetcher: fetch ?? fetcher,
    maxBytes: maxBytes,
    maxEntryBytes: 4000,
    clock: () => now,
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mevora_image_cache_test');
    fetches = 0;
    now = DateTime(2026, 9, 30, 12);
  });

  tearDown(() async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  test(
    'a photo fetched once is served from disk after an app restart',
    () async {
      final first = await cache().load(_storageUrl);
      // A fresh instance over the same directory stands in for a cold start.
      final restarted = cache();
      final second = await restarted.load(_storageUrl);
      expect(fetches, 1);
      expect(second, first);
      expect(restarted.hits, 1);
      expect(restarted.fetches, 0);
    },
  );

  test('concurrent requests for one URL share a single download', () async {
    final gate = Completer<void>();
    final c = cache(
      fetch: (uri) async {
        fetches++;
        await gate.future;
        return _bytes(10);
      },
    );
    final a = c.load(_storageUrl);
    final b = c.load(_storageUrl);
    gate.complete();
    await Future.wait([a, b]);
    expect(fetches, 1);
  });

  test('evicts the least recently used entries past the size budget', () async {
    final c = cache(maxBytes: 2500);
    final urls = ['$_storageUrl&n=1', '$_storageUrl&n=2', '$_storageUrl&n=3'];
    for (final url in urls) {
      await c.load(url);
    }
    // Entry 1 was used most recently; entry 2 is the stalest.
    File(
      '${dir.path}/${ImageDiskCache.keyFor(urls[0])}',
    ).setLastModifiedSync(now);
    File(
      '${dir.path}/${ImageDiskCache.keyFor(urls[1])}',
    ).setLastModifiedSync(now.subtract(const Duration(hours: 2)));
    File(
      '${dir.path}/${ImageDiskCache.keyFor(urls[2])}',
    ).setLastModifiedSync(now.subtract(const Duration(hours: 1)));
    await c.trim();
    final left = dir.listSync().whereType<File>().map(
      (f) => f.uri.pathSegments.last,
    );
    expect(left, isNot(contains(ImageDiskCache.keyFor(urls[1]))));
    expect(left, contains(ImageDiskCache.keyFor(urls[0])));
    final total = dir.listSync().whereType<File>().fold<int>(
      0,
      (s, f) => s + f.lengthSync(),
    );
    expect(total, lessThanOrEqualTo(2500));
  });

  test('an entry idle past maxIdle is fetched again', () async {
    await cache().load(_storageUrl);
    now = now.add(const Duration(days: 31));
    await cache().load(_storageUrl);
    expect(fetches, 2);
  });

  test('an oversized response is served but not stored', () async {
    final c = cache(fetch: (uri) async => _bytes(5000));
    await c.load(_storageUrl);
    expect(dir.listSync(), isEmpty);
  });

  test('no cache directory degrades to a plain network fetch', () async {
    final c = cache(
      directory: () async => throw const FileSystemException('none'),
    );
    await c.load(_storageUrl);
    await c.load(_storageUrl);
    expect(fetches, 2);
  });

  test('a failed fetch is not cached', () async {
    var fail = true;
    final c = cache(
      fetch: (uri) async {
        fetches++;
        if (fail) {
          throw const HttpException('503');
        }
        return _bytes(10);
      },
    );
    await expectLater(c.load(_storageUrl), throwsA(isA<HttpException>()));
    fail = false;
    await c.load(_storageUrl);
    expect(fetches, 2);
  });

  test('clear drops every cached photo', () async {
    final c = cache();
    await c.load(_storageUrl);
    await c.clear();
    expect(dir.listSync(), isEmpty);
    await c.load(_storageUrl);
    expect(fetches, 2);
  });

  test('Storage download URLs get the disk cache; other images do not', () {
    expect(MevoraNetworkImages.isStorageDownloadUrl(_storageUrl), isTrue);
    expect(
      MevoraNetworkImages.isStorageDownloadUrl(
        'http://10.0.2.2:9199/v0/b/demo-mevora.appspot.com/o/users%2Fu1%2Fa.jpg?alt=media&token=t',
      ),
      isTrue,
    );
    expect(
      MevoraNetworkImages.isStorageDownloadUrl(
        'https://media.giphy.com/media/x/giphy.gif',
      ),
      isFalse,
    );
    expect(
      MevoraNetworkImages.provider(_storageUrl),
      isA<DiskCachedNetworkImage>(),
    );
    expect(
      MevoraNetworkImages.provider('https://media.giphy.com/media/x/giphy.gif'),
      isA<NetworkImage>(),
    );
  });

  testWidgets('DiskCachedNetworkImage decodes the cached bytes', (
    tester,
  ) async {
    // 1x1 transparent PNG.
    final png = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1F,
      0x15,
      0xC4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0A,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9C,
      0x63,
      0x00,
      0x01,
      0x00,
      0x00,
      0x05,
      0x00,
      0x01,
      0x0D,
      0x0A,
      0x2D,
      0xB4,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4E,
      0x44,
      0xAE,
      0x42,
      0x60,
      0x82,
    ]);
    await tester.runAsync(() async {
      final c = cache(
        fetch: (uri) async {
          fetches++;
          return png;
        },
      );
      final provider = DiskCachedNetworkImage(_storageUrl, cache: c);
      final completer = Completer<ImageInfo>();
      final stream = provider.resolve(ImageConfiguration.empty);
      stream.addListener(
        ImageStreamListener(
          (info, _) => completer.complete(info),
          onError: (e, s) => completer.completeError(e, s),
        ),
      );
      final info = await completer.future;
      expect(info.image.width, 1);
      expect(fetches, 1);
      expect(provider, DiskCachedNetworkImage(_storageUrl, cache: c));
    });
  });
}
