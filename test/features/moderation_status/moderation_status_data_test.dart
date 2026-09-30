import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/identity/account_status.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/moderation_status/data/callable_moderation_status_repository.dart';
import 'package:mevora/features/moderation_status/domain/models/moderation_status.dart';
import 'package:mevora/features/moderation_status/domain/moderation_reason_category.dart';

class _Backend implements BackendCallable {
  _Backend({this.response = const {}, this.error});

  final Map<String, dynamic> response;
  final Object? error;
  final calls = <(String, Map<String, dynamic>?)>[];

  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    calls.add((name, data));
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return response;
  }
}

const _payload = <String, dynamic>{
  'accountStatus': 'suspended',
  'suspendedUntil': '2030-01-01T10:00:00.000Z',
  'statusReasonCode': 'HARASSMENT',
  'decisions': [
    {
      'actionId': 'act_1',
      'type': 'TEMPORARY_SUSPENSION',
      'reasonCode': 'HARASSMENT',
      'message': 'Please keep conversations respectful.',
      'effectiveAt': '2029-12-25T10:00:00.000Z',
      'expiresAt': '2030-01-01T10:00:00.000Z',
      'overturned': false,
      'appealable': true,
      'appeal': null,
    },
    {
      'actionId': 'act_2',
      'type': 'PHOTO_REJECTED',
      'reasonCode': 'LOW_QUALITY',
      'message': null,
      'effectiveAt': '2029-11-01T10:00:00.000Z',
      'expiresAt': null,
      'overturned': true,
      'appealable': false,
      'appeal': {
        'appealId': 'apl_2',
        'status': 'resolved',
        'decision': 'accepted',
        'message': 'You were right, the photo is fine.',
      },
    },
    {'actionId': '', 'type': 'WARNING'},
  ],
};

void main() {
  group('ModerationStatus.fromMap', () {
    test('reads the callable payload', () {
      final status = ModerationStatus.fromMap(_payload);

      expect(status.accountStatus, AccountStatus.suspended);
      expect(status.suspendedUntil, DateTime.utc(2030, 1, 1, 10));
      expect(status.statusReasonCode, 'HARASSMENT');
      expect(status.decisions, hasLength(2), reason: 'rows without an id drop');

      final suspension = status.decisions.first;
      expect(suspension.type, ModerationDecisionType.temporarySuspension);
      expect(suspension.appealable, isTrue);
      expect(suspension.appeal, isNull);
      expect(suspension.message, 'Please keep conversations respectful.');

      final photo = status.decisions.last;
      expect(photo.type, ModerationDecisionType.photoRejected);
      expect(photo.overturned, isTrue);
      expect(photo.message, isNull);
      expect(photo.appeal?.status, ModerationAppealStatus.resolved);
      expect(photo.appeal?.decision, ModerationAppealDecision.accepted);
      expect(photo.appeal?.message, 'You were right, the photo is fine.');
    });

    test('tolerates an empty or unfamiliar payload', () {
      final status = ModerationStatus.fromMap(const {
        'decisions': [
          {
            'actionId': 'a',
            'type': 'SOMETHING_NEW',
            'appeal': {'status': 'x'},
          },
        ],
      });
      expect(status.accountStatus, AccountStatus.active);
      expect(status.suspendedUntil, isNull);
      expect(status.decisions.single.type, ModerationDecisionType.unknown);
      expect(
        status.decisions.single.appeal?.status,
        ModerationAppealStatus.open,
      );
      expect(status.decisions.single.appeal?.decision, isNull);
    });
  });

  group('reason categories', () {
    test('every backend reason code maps to a safe category', () {
      const expected = {
        'HARASSMENT': ModerationReasonCategory.harmfulBehavior,
        'HATE_SPEECH': ModerationReasonCategory.harmfulBehavior,
        'VIOLENCE_THREATS': ModerationReasonCategory.harmfulBehavior,
        'SCAM_FRAUD': ModerationReasonCategory.scamOrFraud,
        'PAYMENT_ABUSE': ModerationReasonCategory.scamOrFraud,
        'SPAM': ModerationReasonCategory.spam,
        'FAKE_PROFILE': ModerationReasonCategory.authenticity,
        'IMPERSONATION': ModerationReasonCategory.authenticity,
        'BAN_EVASION': ModerationReasonCategory.authenticity,
        'UNDERAGE': ModerationReasonCategory.ageRequirement,
        'INAPPROPRIATE_CONTENT': ModerationReasonCategory.contentRules,
        'NUDITY_SEXUAL_CONTENT': ModerationReasonCategory.contentRules,
        'SELF_HARM_RISK': ModerationReasonCategory.wellbeing,
        'TERMS_VIOLATION': ModerationReasonCategory.general,
        'OTHER': ModerationReasonCategory.general,
        // Photo reject reasons.
        'VIOLENCE_GORE': ModerationReasonCategory.contentRules,
        'HATE_SYMBOLS': ModerationReasonCategory.contentRules,
        'NOT_A_PERSON': ModerationReasonCategory.authenticity,
        'MINOR_IN_PHOTO': ModerationReasonCategory.ageRequirement,
        'LOW_QUALITY': ModerationReasonCategory.photoRequirements,
        'CONTACT_INFO': ModerationReasonCategory.contentRules,
      };
      expected.forEach((code, category) {
        expect(ModerationReasonCategory.fromCode(code), category, reason: code);
      });
    });

    test('unknown or missing codes fall back to the general category', () {
      expect(
        ModerationReasonCategory.fromCode('NEW_CODE_2031'),
        ModerationReasonCategory.general,
      );
      expect(
        ModerationReasonCategory.fromCode(null),
        ModerationReasonCategory.general,
      );
    });
  });

  group('CallableModerationStatusRepository', () {
    test('fetches the member status from getMyModerationStatus', () async {
      final backend = _Backend(response: _payload);
      final repository = CallableModerationStatusRepository(backend: backend);

      final status = await repository.fetchStatus();

      expect(backend.calls.single.$1, 'getMyModerationStatus');
      expect(status.decisions, hasLength(2));
    });

    test('submits a trimmed reason and reports a new appeal', () async {
      final backend = _Backend(response: {'appealId': 'apl', 'created': true});
      final repository = CallableModerationStatusRepository(backend: backend);

      final outcome = await repository.submitAppeal(
        actionId: 'act_1',
        reason: '  This was a misunderstanding.  ',
      );

      expect(outcome, AppealSubmitOutcome.created);
      expect(backend.calls.single.$1, 'submitModerationAppeal');
      expect(backend.calls.single.$2, {
        'actionId': 'act_1',
        'reason': 'This was a misunderstanding.',
      });
    });

    test('an existing appeal is reported as already submitted', () async {
      final repository = CallableModerationStatusRepository(
        backend: _Backend(response: {'appealId': 'apl', 'created': false}),
      );
      expect(
        await repository.submitAppeal(
          actionId: 'act_1',
          reason: 'Second attempt at the same appeal.',
        ),
        AppealSubmitOutcome.alreadySubmitted,
      );
    });

    test(
      'a reason outside 10..2000 characters never reaches the server',
      () async {
        final backend = _Backend();
        final repository = CallableModerationStatusRepository(backend: backend);

        expect(
          await repository.submitAppeal(actionId: 'a', reason: 'too short'),
          AppealSubmitOutcome.invalidReason,
        );
        expect(
          await repository.submitAppeal(actionId: 'a', reason: 'x' * 2001),
          AppealSubmitOutcome.invalidReason,
        );
        expect(backend.calls, isEmpty);
      },
    );

    test('server refusals map to outcomes the member can understand', () async {
      Future<AppealSubmitOutcome> failWith(String code, String message) {
        return CallableModerationStatusRepository(
          backend: _Backend(
            error: FirebaseFunctionsException(code: code, message: message),
          ),
        ).submitAppeal(actionId: 'act_1', reason: 'This decision was wrong.');
      }

      expect(
        await failWith('failed-precondition', 'appeal_window_closed'),
        AppealSubmitOutcome.windowClosed,
      );
      expect(
        await failWith('failed-precondition', 'appeal_not_allowed'),
        AppealSubmitOutcome.notAllowed,
      );
      expect(
        await failWith('invalid-argument', 'reason'),
        AppealSubmitOutcome.invalidReason,
      );
      expect(
        await failWith('invalid-argument', 'actionId'),
        AppealSubmitOutcome.notAllowed,
      );
      expect(
        await failWith('internal', 'appeal-unavailable'),
        AppealSubmitOutcome.failed,
      );
      expect(
        await CallableModerationStatusRepository(
          backend: _Backend(error: StateError('offline')),
        ).submitAppeal(actionId: 'a', reason: 'This decision was wrong.'),
        AppealSubmitOutcome.failed,
      );
    });
  });
}
