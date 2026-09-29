import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/relationship_learning_scope.dart';
import 'package:mevora/core/localization/l10n_errors.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/relationship_learning/domain/entities/relationship_learning.dart';
import 'package:mevora/features/relationship_learning/domain/repositories/relationship_learning_repository.dart';
import 'package:mevora/features/relationship_learning/presentation/controllers/relationship_learning_controller.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/art/mevora_spot.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';
import 'package:mevora/shared/widgets/mevora_meter.dart';
import 'package:mevora/shared/widgets/mevora_selectable_tile.dart';

/// "Mevora seni biraz daha tanısın": one short question per screen.
///
/// Opened after onboarding (the initial set), from the Picks card, and from
/// Profile. [next] is where to go when the member is done; without it the
/// page simply closes.
class RelationshipLearningPage extends StatefulWidget {
  const RelationshipLearningPage({
    super.key,
    this.mode = LearningFlowMode.initial,
    this.next,
    this.source = 'unknown',
    this.repository,
  });

  final LearningFlowMode mode;
  final String? next;
  final String source;

  /// Injected by tests; otherwise read from [RelationshipLearningScope].
  final RelationshipLearningRepository? repository;

  static String location({
    LearningFlowMode mode = LearningFlowMode.initial,
    String? next,
    String? source,
  }) {
    final query = <String, String>{
      if (mode != LearningFlowMode.initial) 'mode': mode.name,
      if (next != null) 'next': next,
      if (source != null) 'source': source,
    };
    return Uri(
      path: AppRoutes.relationshipLearning,
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  @override
  State<RelationshipLearningPage> createState() =>
      _RelationshipLearningPageState();
}

class _RelationshipLearningPageState extends State<RelationshipLearningPage> {
  RelationshipLearningController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) {
      return;
    }
    final scope = RelationshipLearningScope.maybeOf(context);
    final repository = widget.repository ?? scope?.repository;
    if (repository == null) {
      return;
    }
    _controller = RelationshipLearningController(
      repository: repository,
      mode: widget.mode,
      analytics: scope?.analytics,
      source: widget.source,
    )..addListener(_onChange);
    unawaited(_controller!.load());
  }

  @override
  void dispose() {
    _controller?.removeListener(_onChange);
    _controller?.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) {
      return;
    }
    final error = _controller?.takeActionError();
    if (error != null) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            error.isEmpty
                ? l10n.learningSaveFailed
                : L10nErrors.message(l10n, error),
          ),
        ),
      );
    }
    setState(() {});
  }

  Future<void> _leave() async {
    // Finishing the initial questions is a journey step: read the new stage
    // first so the router does not bounce the member back here.
    await RelationshipLearningScope.maybeOf(context)?.journey?.refresh();
    if (!mounted) {
      return;
    }
    final next = widget.next;
    final router = GoRouter.maybeOf(context);
    if (next != null && next.startsWith('/') && router != null) {
      router.go(next);
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(true);
    } else if (router != null) {
      router.go(AppRoutes.discovery);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.close,
          onPressed: _leave,
          icon: const Icon(MevoraIcons.close),
        ),
      ),
      body: SafeArea(
        child: controller == null
            ? const MevoraLoading.page()
            : AnimatedSwitcher(
                duration:
                    (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
                    ? Duration.zero
                    : AppDurations.normal,
                child: _body(context, controller),
              ),
      ),
    );
  }

  Widget _body(BuildContext context, RelationshipLearningController c) {
    final l10n = AppLocalizations.of(context);
    return switch (c.phase) {
      LearningFlowPhase.loading => const MevoraLoading.page(
        key: ValueKey('learning-loading'),
      ),
      LearningFlowPhase.error => MevoraErrorView(
        key: const ValueKey('learning-error'),
        title: l10n.learningLoadErrorTitle,
        message: L10nErrors.message(l10n, c.loadError),
        onRetry: () => unawaited(c.load()),
      ),
      LearningFlowPhase.nothingToAsk => MevoraEmptyState(
        key: const ValueKey('learning-nothing'),
        art: MevoraArt.questions,
        title: l10n.learningNothingTitle,
        message: l10n.learningNothingBody,
        actionLabel: l10n.close,
        onAction: _leave,
      ),
      LearningFlowPhase.intro => _Intro(
        key: const ValueKey('learning-intro'),
        total: c.total,
        onStart: c.begin,
        // Straight after the Humor Lab: say what just happened and what is
        // next, in one line each.
        afterHumor: widget.source == 'journey' && c.summary.humorCalibrated,
      ),
      LearningFlowPhase.question => _QuestionView(
        key: const ValueKey('learning-question'),
        controller: c,
      ),
      LearningFlowPhase.done => _Done(
        key: const ValueKey('learning-done'),
        followUp: c.isFollowUp,
        onContinue: _leave,
      ),
    };
  }
}

class _Intro extends StatelessWidget {
  const _Intro({
    super.key,
    required this.total,
    required this.onStart,
    this.afterHumor = false,
  });

  final int total;
  final VoidCallback onStart;
  final bool afterHumor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: Column(
        children: [
          const Spacer(),
          const MevoraSpot(art: MevoraArt.questions),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            header: true,
            child: Text(
              afterHumor
                  ? l10n.learningAfterHumorTitle
                  : l10n.learningIntroTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            afterHumor ? l10n.learningAfterHumorBody : l10n.learningIntroBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.learningIntroMeta(total),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const Spacer(),
          MevoraButton(
            key: const Key('learningStartButton'),
            label: l10n.learningIntroStart,
            onPressed: onStart,
          ),
        ],
      ),
    );
  }
}

class _QuestionView extends StatelessWidget {
  const _QuestionView({super.key, required this.controller});

  final RelationshipLearningController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final question = controller.current!;
    final language = Localizations.localeOf(context).languageCode;
    final position = controller.index + 1;
    final total = controller.total;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.sm,
        AppSpacing.screenPadding,
        AppSpacing.screenPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: l10n.learningProgressSemantics(position, total),
            excludeSemantics: true,
            child: Row(
              children: [
                Text(
                  l10n.learningProgress(position, total),
                  key: const Key('learningProgressLabel'),
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: MevoraMeter(
                    value: controller.answeredCount / (total == 0 ? 1 : total),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Expanded(
            child: AnimatedSwitcher(
              duration: still ? Duration.zero : AppDurations.normal,
              switchInCurve: AppCurves.enter,
              child: ListView(
                key: ValueKey(question.id),
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      question.promptFor(language),
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  for (final option in question.options)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                      child: MevoraSelectableTile(
                        key: Key('learningOption_${option.id}'),
                        title: option.labelFor(language),
                        selected: question.answerId == option.id,
                        onTap: controller.saving
                            ? null
                            : () => unawaited(controller.choose(option.id)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: MevoraButton(
                  key: const Key('learningPreviousButton'),
                  label: l10n.learningPrevious,
                  variant: MevoraButtonVariant.ghost,
                  onPressed: controller.canGoBack ? controller.back : null,
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: MevoraButton(
                  key: const Key('learningNextButton'),
                  label: l10n.learningNext,
                  variant: MevoraButtonVariant.secondary,
                  isLoading: controller.saving,
                  onPressed: controller.canGoForward
                      ? controller.forward
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({super.key, required this.followUp, required this.onContinue});

  final bool followUp;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MevoraEmptyState(
      art: MevoraArt.success,
      title: followUp ? l10n.learningFollowUpDoneTitle : l10n.learningDoneTitle,
      message: followUp ? l10n.learningFollowUpDoneBody : l10n.learningDoneBody,
      actionLabel: l10n.learningDoneContinue,
      onAction: onContinue,
    );
  }
}

/// Parses the route's `mode` query parameter.
LearningFlowMode learningModeFromQuery(String? raw) =>
    LearningFlowMode.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => LearningFlowMode.initial,
    );

/// Opens the flow that fits [summary]: the initial set while it is
/// unfinished, otherwise a follow-up round. Resolves true when the member
/// came back from it, so callers can refresh.
Future<void> openRelationshipLearning(
  BuildContext context, {
  required LearningSummary summary,
  required String source,
}) async {
  final mode = summary.initialCompleted
      ? LearningFlowMode.followUp
      : LearningFlowMode.initial;
  final router = GoRouter.maybeOf(context);
  if (router != null) {
    await router.push<Object?>(
      RelationshipLearningPage.location(mode: mode, source: source),
    );
    return;
  }
  await Navigator.of(context).push<Object?>(
    MaterialPageRoute<Object?>(
      builder: (_) => RelationshipLearningPage(mode: mode, source: source),
    ),
  );
}
