import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/cache/image_disk_cache.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';

void main() {
  test('accepts only http(s) photo URLs', () {
    expect(MevoraNetworkImages.isHttpUrl(null), isFalse);
    expect(MevoraNetworkImages.isHttpUrl(''), isFalse);
    expect(MevoraNetworkImages.isHttpUrl('mock://uid/0'), isFalse);
    expect(MevoraNetworkImages.isHttpUrl('file:///tmp/a.jpg'), isFalse);
    expect(
      MevoraNetworkImages.isHttpUrl('https://cdn.example/photo.jpg'),
      isTrue,
    );
    expect(MevoraNetworkImages.provider('mock://uid/0'), isNull);
    expect(
      MevoraNetworkImages.provider('https://cdn.example/photo.jpg'),
      isA<NetworkImage>(),
    );
    expect(
      MevoraNetworkImages.provider('assets/images/portraits/mock-08.jpg'),
      isA<AssetImage>(),
    );
    expect(
      MevoraNetworkImages.provider('mock://mock-08/0'),
      isA<AssetImage>(),
    );
  });

  group('against the Emulator Suite', () {
    const published =
        'https://firebasestorage.googleapis.com/v0/b/mevora.appspot.com/o/'
        'users%2Fu1%2Fprofile%2Fthumbs%2Fimg1_card.jpg?alt=media&token=t1';

    tearDown(() => MevoraNetworkImages.emulatorStorageOrigin = null);

    test('a production build never rewrites a photo URL', () {
      expect(MevoraNetworkImages.resolve(published), published);
    });

    test('a published photo is fetched from the Storage emulator', () {
      MevoraNetworkImages.emulatorStorageOrigin = 'http://10.0.2.2:9199';

      final resolved = Uri.parse(MevoraNetworkImages.resolve(published)!);
      final original = Uri.parse(published);
      expect(resolved.scheme, 'http');
      expect(resolved.host, '10.0.2.2');
      expect(resolved.port, 9199);
      // The object and its token are the same on both hosts.
      expect(resolved.path, original.path);
      expect(resolved.queryParameters, original.queryParameters);

      final provider = MevoraNetworkImages.provider(published);
      expect(provider, isA<DiskCachedNetworkImage>());
      expect((provider! as DiskCachedNetworkImage).url, resolved.toString());
    });

    test('other images are left alone', () {
      MevoraNetworkImages.emulatorStorageOrigin = 'http://10.0.2.2:9199';
      const emulatorUrl =
          'http://10.0.2.2:9199/v0/b/demo.appspot.com/o/users%2Fu1%2Fa.jpg'
          '?alt=media&token=t';
      const gif = 'https://media.giphy.com/media/x/giphy.gif';

      expect(MevoraNetworkImages.resolve(emulatorUrl), emulatorUrl);
      expect(MevoraNetworkImages.resolve(gif), gif);
      expect(MevoraNetworkImages.resolve(null), isNull);
    });
  });
}
