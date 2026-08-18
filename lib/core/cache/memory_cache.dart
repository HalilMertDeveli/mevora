/// In-memory TTL cache. Never the source of truth — backends remain canonical.
class MemoryCache<K, V> {
  MemoryCache({
    this.ttl = const Duration(minutes: 5),
    this.maxEntries = 100,
  });

  final Duration ttl;
  final int maxEntries;
  final Map<K, _Entry<V>> _entries = {};

  V? get(K key) {
    final entry = _entries[key];
    if (entry == null) {
      return null;
    }
    if (entry.expiresAt.isBefore(DateTime.now())) {
      _entries.remove(key);
      return null;
    }
    return entry.value;
  }

  void set(K key, V value) {
    if (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = _Entry(
      value: value,
      expiresAt: DateTime.now().add(ttl),
    );
  }

  void invalidate(K key) => _entries.remove(key);

  void clear() => _entries.clear();
}

class _Entry<V> {
  const _Entry({required this.value, required this.expiresAt});

  final V value;
  final DateTime expiresAt;
}
