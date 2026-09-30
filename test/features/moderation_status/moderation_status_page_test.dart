import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/moderation_status_scope.dart';
import 'package:mevora/core/identity/account_status.dart';
import 'package:mevora/features/moderation_status/domain/models/moderation_status.dart';
import 'package:mevora/features/moderation_status/domain/repositories/moderation_status_repository.dart';
import 'package:mevora/features/moderation_status/presentation/pages/moderation_status_page.dart';

import '../../helpers/l10n_harness.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nEn();

ModerationDecision _suspension({
  bool appealable = true,
  ModerationAppeal? appeal,
  bool overturned = false,
}) {
  return ModerationDecision(
    actionId: 'act_1',
    type: ModerationDecisionType.temporarySuspension,
    reasonCode: 'HARASSMENT',
    message: 'Please keep conversations respectful.',
    effectiveAt: DateTime.utc(2029, 12, 25),
    expiresAt: DateTime.utc(2030, 1, 1),
    appealable: appealable,
    appeal: appeal,
    overturned: overturned,
  );
}

ModerationStatus _suspended(List<ModerationDecision> decisions) {
  return ModerationStatus(
    accountStatus: AccountStatus.suspended,
    suspendedUntil: DateTime.utc(2030, 1, 1),
    statusReasonCode: 'HARASSMENT',
    decisions: decisions,
  );
}

class _FakeRepository implements ModerationStatusRepository {
  _FakeRepository(this.status, {this.outcome = AppealSubmitOutcome.created});

  ModerationStatus status;
  AppealSubmitOutcome outcome;
  bool failFetch = false;
  int fetches = 0;
  final submissions = <(String, String)>[];

  /// What the server knows after a submit that filed or found an appeal.
  ModerationStatus? afterSubmit;

  @override
  Future<ModerationStatus> fetchStatus() async {
    fetches += 1;
    if (failFetch) {
      throw StateError('offline');
    }
    return status;
  }

  @override
  Future<AppealSubmitOutcome> submitAppeal({
    required String actionId,
    required String reason,
  }) async {
    submissions.add((actionId, reason));
    final next = afterSubmit;
    if (next != null) {
      status = next;
    }
    return outcome;
  }
}

Future<void> _pump(WidgetTester tester, _FakeRepository repository) async {
  await tester.pumpWidget(
    ModerationStatusScope(
      repository: repository,
      child: wrapWithApp(const ModerationStatusPage(), scaffold: false),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _submitAppeal(WidgetTester tester, String reason) async {
  await tester.tap(find.byKey(const ValueKey('appeal-act_1')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('appeal-reason')), reason);
  await tester.tap(find.byKey(const ValueKey('appeal-submit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the status, a safe reason and the decisions', (
    tester,
  ) async {
    final repository = _FakeRepository(
      _suspended([
        _suspension(),
        const ModerationDecision(
          actionId: 'act_2',
          type: ModerationDecisionType.photoRejected,
          reasonCode: 'LOW_QUALITY',
          overturned: true,
          appeal: ModerationAppeal(
            appealId: 'apl_2',
            status: ModerationAppealStatus.resolved,
            decision: ModerationAppealDecision.accepted,
            message: 'You were right, the photo is fine.',
          ),
        ),
        const ModerationDecision(
          actionId: 'act_3',
          type: ModerationDecisionType.warning,
          reasonCode: 'SPAM',
        ),
      ]),
    );
    await _pump(tester, repository);

    expect(repository.fetches, 1);
    expect(find.text(_l10n.moderationStatusSuspended), findsOneWidget);
    expect(
      find.text(
        _l10n.moderationStatusReason(_l10n.moderationReasonHarmfulBehavior),
      ),
      findsNWidgets(2),
    );
    // The raw staff code never shows.
    expect(find.textContaining('HARASSMENT'), findsNothing);
    expect(find.text(_l10n.moderationTypeTemporarySuspension), findsOneWidget);
    expect(find.text('Please keep conversations respectful.'), findsOneWidget);
    expect(find.text(_l10n.moderationAppealAction), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text(_l10n.moderationTypeWarning),
      200,
    );
    expect(find.text(_l10n.moderationTypePhotoRejected), findsOneWidget);
    expect(find.text(_l10n.moderationDecisionReversed), findsOneWidget);
    expect(find.text(_l10n.moderationAppealAccepted), findsOneWidget);
    expect(find.text('You were right, the photo is fine.'), findsOneWidget);
    // Not appealable, no appeal, not reversed: the window has closed.
    expect(find.text(_l10n.moderationAppealWindowClosed), findsOneWidget);
  });

  testWidgets('an active member with no decisions sees a clean record', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeRepository(
        const ModerationStatus(accountStatus: AccountStatus.active),
      ),
    );

    expect(find.text(_l10n.moderationStatusActive), findsOneWidget);
    expect(find.text(_l10n.moderationDecisionsEmpty), findsOneWidget);
  });

  testWidgets('submitting an appeal files it and shows it as received', (
    tester,
  ) async {
    final repository = _FakeRepository(_suspended([_suspension()]))
      ..afterSubmit = _suspended([
        _suspension(
          appealable: false,
          appeal: const ModerationAppeal(
            appealId: 'apl_1',
            status: ModerationAppealStatus.open,
          ),
        ),
      ]);
    await _pump(tester, repository);

    await _submitAppeal(tester, 'I was quoting a friend, not insulting.');

    expect(repository.submissions, [
      ('act_1', 'I was quoting a friend, not insulting.'),
    ]);
    expect(find.text(_l10n.moderationAppealSent), findsOneWidget);
    expect(find.text(_l10n.moderationAppealOpen), findsOneWidget);
    expect(find.text(_l10n.moderationAppealAction), findsNothing);
    expect(repository.fetches, 2, reason: 'reloaded after the submit');
  });

  testWidgets('a too-short reason is caught before anything is sent', (
    tester,
  ) async {
    final repository = _FakeRepository(_suspended([_suspension()]));
    await _pump(tester, repository);

    await _submitAppeal(tester, 'short');

    expect(find.text(_l10n.moderationAppealReasonTooShort), findsOneWidget);
    expect(repository.submissions, isEmpty);
  });

  testWidgets('a duplicate appeal says it was already submitted', (
    tester,
  ) async {
    final repository = _FakeRepository(
      _suspended([_suspension()]),
      outcome: AppealSubmitOutcome.alreadySubmitted,
    );
    await _pump(tester, repository);

    await _submitAppeal(tester, 'Please look at this decision again.');

    expect(find.text(_l10n.moderationAppealAlreadySent), findsOneWidget);
  });

  testWidgets('a failed submit says so and keeps the appeal available', (
    tester,
  ) async {
    final repository = _FakeRepository(
      _suspended([_suspension()]),
      outcome: AppealSubmitOutcome.failed,
    );
    await _pump(tester, repository);

    await _submitAppeal(tester, 'Please look at this decision again.');

    expect(find.text(_l10n.moderationAppealFailed), findsOneWidget);
    expect(find.byKey(const ValueKey('appeal-act_1')), findsOneWidget);
    expect(repository.fetches, 1, reason: 'nothing changed server-side');
  });

  testWidgets('a closed window is explained when the server refuses', (
    tester,
  ) async {
    final repository = _FakeRepository(
      _suspended([_suspension()]),
      outcome: AppealSubmitOutcome.windowClosed,
    )..afterSubmit = _suspended([_suspension(appealable: false)]);
    await _pump(tester, repository);

    await _submitAppeal(tester, 'Please look at this decision again.');

    // Once in the snackbar, once on the refreshed decision.
    expect(find.text(_l10n.moderationAppealWindowClosed), findsNWidgets(2));
    expect(find.byKey(const ValueKey('appeal-act_1')), findsNothing);
  });

  testWidgets('refreshing shows the reviewer\'s decision', (tester) async {
    final repository = _FakeRepository(
      _suspended([
        _suspension(
          appealable: false,
          appeal: const ModerationAppeal(
            appealId: 'apl_1',
            status: ModerationAppealStatus.inReview,
          ),
        ),
      ]),
    );
    await _pump(tester, repository);
    expect(find.text(_l10n.moderationAppealInReview), findsOneWidget);

    // Staff reject the appeal meanwhile.
    repository.status = _suspended([
      _suspension(
        appealable: false,
        appeal: const ModerationAppeal(
          appealId: 'apl_1',
          status: ModerationAppealStatus.resolved,
          decision: ModerationAppealDecision.rejected,
          message: 'The messages break our harassment rules.',
        ),
      ),
    ]);
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(repository.fetches, 2);
    expect(find.text(_l10n.moderationAppealRejected), findsOneWidget);
    expect(
      find.text('The messages break our harassment rules.'),
      findsOneWidget,
    );

    // Accepted on a later review: the account is active again (on resume).
    repository.status = ModerationStatus(
      accountStatus: AccountStatus.active,
      decisions: [
        _suspension(
          appealable: false,
          overturned: true,
          appeal: const ModerationAppeal(
            appealId: 'apl_1',
            status: ModerationAppealStatus.resolved,
            decision: ModerationAppealDecision.accepted,
          ),
        ),
      ],
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(repository.fetches, 3);
    expect(find.text(_l10n.moderationStatusActive), findsOneWidget);
    expect(find.text(_l10n.moderationAppealAccepted), findsOneWidget);
  });

  testWidgets('a failed first load offers a retry', (tester) async {
    final repository = _FakeRepository(_suspended(const []))..failFetch = true;
    await _pump(tester, repository);

    expect(find.text(_l10n.moderationStatusLoadFailed), findsOneWidget);

    repository.failFetch = false;
    await tester.tap(find.text(_l10n.retry));
    await tester.pumpAndSettle();

    expect(find.text(_l10n.moderationStatusSuspended), findsOneWidget);
  });
}
