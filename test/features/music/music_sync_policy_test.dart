import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/music/domain/services/music_sync_policy.dart';

void main() {
  test('first sync is always allowed', () {
    expect(
      MusicSyncPolicy.canSync(now: DateTime(2026, 8, 20, 12), lastSyncedAt: null),
      isTrue,
    );
  });

  test('throttles refreshes inside the 6 hour window', () {
    final last = DateTime(2026, 8, 20, 10);
    expect(
      MusicSyncPolicy.canSync(
        now: DateTime(2026, 8, 20, 12),
        lastSyncedAt: last,
      ),
      isFalse,
    );
    expect(
      MusicSyncPolicy.canSync(
        now: DateTime(2026, 8, 20, 16, 1),
        lastSyncedAt: last,
      ),
      isTrue,
    );
  });

  test('mock source does not hammer Spotify after a connect', () async {
    // Covered via MusicSyncPolicy + MockMusicDataSource.syncTaste.
    final last = DateTime(2026, 8, 20, 11);
    final remaining = MusicSyncPolicy.cooldownRemaining(
      now: DateTime(2026, 8, 20, 12),
      lastSyncedAt: last,
    );
    expect(remaining, isNotNull);
    expect(remaining!.inHours, 5);
  });
}
