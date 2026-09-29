import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/personalization/domain/profile_engagement_tracker.dart';

void main() {
  test('reports one visit exactly once, with only coarse metadata', () {
    final tracker = ProfileEngagementTracker(candidateUid: 'c1')..start();
    tracker
      ..photoViewed(1)
      ..photoViewed(1)
      ..photoViewed(3)
      ..spotifySectionSeen();

    final payload = tracker.finish()!;
    expect(payload.keys.toSet(), {
      'candidateUid',
      'detailsOpened',
      'photosViewed',
      'spotifyOpened',
      'whyThisPersonOpened',
      'dwellMs',
    });
    expect(payload['candidateUid'], 'c1');
    expect(payload['detailsOpened'], isTrue);
    expect(payload['photosViewed'], 3, reason: 'first photo plus 1 and 3');
    expect(payload['spotifyOpened'], isTrue);
    expect(payload['whyThisPersonOpened'], isFalse);
    expect(
      tracker.finish(),
      isNull,
      reason: 'a rebuild or second dispose sends nothing',
    );
  });

  test('stops counting dwell while the app is in the background', () {
    final watch = Stopwatch();
    final tracker = ProfileEngagementTracker(
      candidateUid: 'c1',
      stopwatch: watch,
    )..start();
    expect(watch.isRunning, isTrue);
    tracker.pause();
    expect(watch.isRunning, isFalse);
    tracker.start();
    expect(
      watch.isRunning,
      isFalse,
      reason: 'start while backgrounded is ignored',
    );
    tracker.resume();
    expect(watch.isRunning, isTrue);
    tracker.finish();
    expect(watch.isRunning, isFalse);
    tracker.resume();
    expect(watch.isRunning, isFalse, reason: 'a finished visit never restarts');
  });
}
