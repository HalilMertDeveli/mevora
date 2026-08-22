import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
