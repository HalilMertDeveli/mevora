import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/cache/memory_cache.dart';

void main() {
  test('memory cache expires entries and is never source of truth', () async {
    final cache = MemoryCache<String, int>(
      ttl: const Duration(milliseconds: 20),
      maxEntries: 2,
    );

    cache.set('a', 1);
    expect(cache.get('a'), 1);

    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(cache.get('a'), isNull);
  });
}
