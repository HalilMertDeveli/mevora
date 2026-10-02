import 'dart:collection';
import 'dart:typed_data';

/// Decrypted chat media, in memory only, keyed by message.
///
/// The message window is a live query: every snapshot (a new message, a read
/// receipt, typing into the thread) re-ran decryptMessages over the whole
/// window, and each image or voice note in it was downloaded from Storage and
/// decrypted again. A message's media never changes, so the first decryption
/// can be reused for as long as the thread stays warm.
///
/// Plaintext never touches disk — that would weaken the end-to-end guarantee
/// at rest. Bounded by [maxBytes], least-recently-used evicted first; cleared
/// with the E2EE sessions on sign-out.
class DecryptedMediaCache {
  DecryptedMediaCache({this.maxBytes = 32 * 1024 * 1024});

  final int maxBytes;

  final LinkedHashMap<String, Uint8List> _entries =
      LinkedHashMap<String, Uint8List>();
  int _bytes = 0;

  int get length => _entries.length;
  int get bytes => _bytes;

  /// Message ids are only unique per match; the storage path pins the exact
  /// blob, so a reused id can never serve another message's media.
  static String keyFor({
    required String matchId,
    required String messageId,
    required String storagePath,
  }) => '$matchId/$messageId/$storagePath';

  Uint8List? get(String key) {
    final value = _entries.remove(key);
    if (value != null) {
      _entries[key] = value; // most recently used goes last
    }
    return value;
  }

  void put(String key, Uint8List value) {
    if (value.length > maxBytes) {
      return;
    }
    remove(key);
    _entries[key] = value;
    _bytes += value.length;
    while (_bytes > maxBytes && _entries.isNotEmpty) {
      remove(_entries.keys.first);
    }
  }

  void remove(String key) {
    final old = _entries.remove(key);
    if (old != null) {
      _bytes -= old.length;
    }
  }

  void removeMatch(String matchId) {
    final prefix = '$matchId/';
    for (final key
        in _entries.keys.where((k) => k.startsWith(prefix)).toList()) {
      remove(key);
    }
  }

  void clear() {
    _entries.clear();
    _bytes = 0;
  }
}
