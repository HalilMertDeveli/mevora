import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/safety/domain/models/report_reason.dart';
import 'package:mevora/features/safety/domain/safety_policy.dart';

void main() {
  group('report compliance', () {
    test('report reasons map to server whitelist values', () {
      final values = ReportReason.values.map((reason) => reason.firestoreValue).toSet();
      expect(values, containsAll(<String>[
        'spam',
        'harassment',
        'inappropriate_content',
        'scam',
        'fake_profile',
        'underage',
        'other',
      ]));
      expect(values.length, ReportReason.values.length);
    });

    test('underage and fake profile reasons are available in UI', () {
      expect(ReportReason.underage.label, 'Underage');
      expect(ReportReason.fakeProfile.label, 'Fake Profile');
    });
  });

  group('block compliance', () {
    test('block ids are directional but checked symmetrically', () {
      final blockId = SafetyPolicy.blockId(blockerId: 'viewer', blockedUserId: 'target');
      expect(blockId, 'viewer_target');
      expect(
        SafetyPolicy.isBlocked(
          blockIds: {blockId},
          uidA: 'viewer',
          uidB: 'target',
        ),
        isTrue,
      );
      expect(
        SafetyPolicy.isBlocked(
          blockIds: {blockId},
          uidA: 'target',
          uidB: 'viewer',
        ),
        isTrue,
      );
    });

    test('blocked users cannot interact or create matches', () {
      expect(
        SafetyPolicy.canInteract(matchActive: true, blocked: true),
        isFalse,
      );
      expect(SafetyPolicy.canCreateMatch(blocked: true), isFalse);
      expect(
        SafetyPolicy.canInteract(matchActive: true, blocked: false),
        isTrue,
      );
    });
  });
}
