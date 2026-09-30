import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/moderation_status_scope.dart';
import 'package:mevora/core/identity/account_status.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/moderation_status/domain/models/moderation_status.dart';
import 'package:mevora/features/moderation_status/presentation/controllers/moderation_status_controller.dart';
import 'package:mevora/features/moderation_status/presentation/moderation_labels.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/art/mevora_spot.dart';
import 'package:mevora/shared/widgets/mevora_banner.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// "Why is my account restricted?" — the member's own moderation record:
/// account status, a safe reason category, each decision with its appeal
/// state, and the way to appeal. Reloads on open, pull and resume, so a
/// decision staff made meanwhile (an accepted or rejected appeal) shows up.
class ModerationStatusPage extends StatefulWidget {
  const ModerationStatusPage({super.key});

  @override
  State<ModerationStatusPage> createState() => _ModerationStatusPageState();
}

class _ModerationStatusPageState extends State<ModerationStatusPage>
    with WidgetsBindingObserver {
  ModerationStatusController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) {
      return;
    }
    final repository = ModerationStatusScope.maybeRepositoryOf(context);
    if (repository == null) {
      return;
    }
    _controller = ModerationStatusController(repository: repository);
    unawaited(_controller!.refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller?.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _appeal(ModerationDecision decision) async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AppealSheet(),
    );
    if (reason == null || !mounted) {
      return;
    }
    final outcome = await controller.submitAppeal(
      actionId: decision.actionId,
      reason: reason,
    );
    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ModerationLabels.appealOutcome(l10n, outcome))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.moderationStatusTitle)),
      body: SafeArea(
        child: controller == null
            ? MevoraErrorView(
                art: MevoraArt.error,
                title: l10n.somethingWentWrong,
                message: l10n.moderationStatusLoadFailed,
              )
            : ListenableBuilder(
                listenable: controller,
                builder: (context, _) => _body(context, controller),
              ),
      ),
    );
  }

  Widget _body(BuildContext context, ModerationStatusController controller) {
    final l10n = AppLocalizations.of(context);
    final status = controller.status;
    if (status == null) {
      if (controller.loadFailed) {
        return MevoraErrorView(
          art: MevoraArt.error,
          title: l10n.somethingWentWrong,
          message: l10n.moderationStatusLoadFailed,
          onRetry: () => unawaited(controller.refresh()),
        );
      }
      return MevoraLoading.page(message: l10n.loading);
    }
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        children: [
          if (controller.loadFailed) ...[
            MevoraBanner(
              tone: MevoraTone.warning,
              message: l10n.moderationStatusLoadFailed,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          _StatusCard(status: status),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.moderationDecisionsTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (status.decisions.isEmpty)
            Text(l10n.moderationDecisionsEmpty)
          else
            for (final decision in status.decisions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                child: _DecisionCard(
                  decision: decision,
                  submitting:
                      controller.submittingActionId == decision.actionId,
                  onAppeal: controller.submittingActionId == null
                      ? () => unawaited(_appeal(decision))
                      : null,
                ),
              ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final ModerationStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final restricted = status.accountStatus != AccountStatus.active;
    final until = status.suspendedUntil;
    return MevoraCard(
      emphasis: MevoraCardEmphasis.quiet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                restricted ? MevoraIcons.safety : MevoraIcons.successOutline,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  ModerationLabels.accountStatus(l10n, status.accountStatus),
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          if (restricted) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.moderationStatusReason(
                ModerationLabels.reason(l10n, status.statusReasonCode),
              ),
            ),
          ],
          if (status.accountStatus == AccountStatus.suspended) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              until != null
                  ? l10n.accountRestrictedUntil(
                      ModerationLabels.dateTime(context, until),
                    )
                  : l10n.accountRestrictedOpenEnded,
            ),
          ],
        ],
      ),
    );
  }
}

class _DecisionCard extends StatelessWidget {
  const _DecisionCard({
    required this.decision,
    required this.submitting,
    required this.onAppeal,
  });

  final ModerationDecision decision;
  final bool submitting;
  final VoidCallback? onAppeal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final effectiveAt = decision.effectiveAt;
    final expiresAt = decision.expiresAt;
    final message = decision.message;
    return MevoraCard(
      key: ValueKey('moderation-decision-${decision.actionId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ModerationLabels.decisionType(l10n, decision.type),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (decision.overturned)
                MevoraPill(
                  label: l10n.moderationDecisionReversed,
                  tone: MevoraTone.success,
                  dense: true,
                ),
            ],
          ),
          if (effectiveAt != null)
            Text(
              ModerationLabels.dateTime(context, effectiveAt),
              style: theme.textTheme.labelSmall,
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.moderationStatusReason(
              ModerationLabels.reason(l10n, decision.reasonCode),
            ),
          ),
          if (expiresAt != null && !decision.overturned)
            Text(
              l10n.moderationDecisionUntil(
                ModerationLabels.dateTime(context, expiresAt),
              ),
            ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(message),
          ],
          const SizedBox(height: AppSpacing.s12),
          _AppealState(
            decision: decision,
            submitting: submitting,
            onAppeal: onAppeal,
          ),
        ],
      ),
    );
  }
}

class _AppealState extends StatelessWidget {
  const _AppealState({
    required this.decision,
    required this.submitting,
    required this.onAppeal,
  });

  final ModerationDecision decision;
  final bool submitting;
  final VoidCallback? onAppeal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final appeal = decision.appeal;
    if (appeal != null) {
      if (appeal.status != ModerationAppealStatus.resolved) {
        return Text(
          appeal.status == ModerationAppealStatus.inReview
              ? l10n.moderationAppealInReview
              : l10n.moderationAppealOpen,
        );
      }
      final (label, tone) = switch (appeal.decision) {
        ModerationAppealDecision.accepted => (
          l10n.moderationAppealAccepted,
          MevoraTone.success,
        ),
        ModerationAppealDecision.rejected => (
          l10n.moderationAppealRejected,
          MevoraTone.neutral,
        ),
        null => (l10n.moderationAppealResolved, MevoraTone.neutral),
      };
      final message = appeal.message;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MevoraPill(label: label, tone: tone, dense: true),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(message, style: theme.textTheme.bodyMedium),
          ],
        ],
      );
    }
    if (decision.appealable) {
      return MevoraButton(
        key: ValueKey('appeal-${decision.actionId}'),
        label: l10n.moderationAppealAction,
        variant: MevoraButtonVariant.secondary,
        size: MevoraButtonSize.small,
        isExpanded: false,
        isLoading: submitting,
        onPressed: onAppeal,
      );
    }
    if (decision.overturned) {
      return const SizedBox.shrink();
    }
    return Text(
      l10n.moderationAppealWindowClosed,
      style: theme.textTheme.bodySmall,
    );
  }
}

/// Collects the appeal reason; pops with the text, or nothing if dismissed.
class _AppealSheet extends StatefulWidget {
  const _AppealSheet();

  @override
  State<_AppealSheet> createState() => _AppealSheetState();
}

class _AppealSheetState extends State<_AppealSheet> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = AppLocalizations.of(context);
    final reason = _text.text.trim();
    if (reason.length < AppealReasonRules.minLength) {
      setState(() => _error = l10n.moderationAppealReasonTooShort);
      return;
    }
    if (!AppealReasonRules.isValid(reason)) {
      setState(() => _error = l10n.moderationAppealInvalid);
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        0,
        AppSpacing.screenPadding,
        AppSpacing.screenPadding + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.moderationAppealAction,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(l10n.moderationAppealSheetBody),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('appeal-reason'),
              controller: _text,
              minLines: 4,
              maxLines: 8,
              maxLength: AppealReasonRules.maxLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.moderationAppealReasonLabel,
                hintText: l10n.moderationAppealReasonHint,
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_error != null) {
                  setState(() => _error = null);
                }
              },
            ),
            const SizedBox(height: AppSpacing.md),
            MevoraButton(
              key: const ValueKey('appeal-submit'),
              label: l10n.moderationAppealSubmit,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
