import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/localization/l10n_errors.dart';
import 'package:mevora/features/picks/domain/entities/mevora_pick.dart';
import 'package:mevora/features/picks/presentation/controllers/mevora_picks_controller.dart';
import 'package:mevora/features/picks/presentation/widgets/pick_card.dart';
import 'package:mevora/features/relationship_learning/domain/entities/relationship_learning.dart';
import 'package:mevora/features/relationship_learning/presentation/widgets/learning_prompt_card.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/art/mevora_spot.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

/// The Mevora Picks screen body: today's short, explained, finite set of
/// people Mevora chose. When it runs out, it runs out until tomorrow.
class PicksView extends StatefulWidget {
  const PicksView({
    super.key,
    required this.controller,
    required this.onOpenProfile,
    this.onOpenLearning,
    this.onSkipLearningToday,
    this.onOpenSettings,
    this.footer,
  });

  final MevoraPicksController controller;
  final void Function(MevoraPick pick) onOpenProfile;

  /// Opens today's relationship questions. Without it no card is shown.
  final void Function(LearningSummary summary)? onOpenLearning;

  /// "Bugünlük geç" on today's questions card.
  final void Function(LearningSummary summary)? onSkipLearningToday;
  final VoidCallback? onOpenSettings;

  /// Shown under the Picks (e.g. the Humor Lab entry, whose calibration is
  /// what makes a Humor Match possible).
  final Widget? footer;

  @override
  State<PicksView> createState() => _PicksViewState();
}

class _PicksViewState extends State<PicksView> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void didUpdateWidget(covariant PicksView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChange);
      widget.controller.addListener(_onChange);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) {
      return;
    }
    final error = widget.controller.state.actionErrorMessage;
    if (error != null) {
      widget.controller.clearActionError();
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            error.isEmpty
                ? l10n.picksActionFailed
                : L10nErrors.message(l10n, error),
          ),
        ),
      );
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = widget.controller.state;
    return AnimatedSwitcher(
      duration: (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
          ? Duration.zero
          : AppDurations.normal,
      child: switch (state.phase) {
        PicksPhase.initial || PicksPhase.loading => MevoraLoading.page(
          key: const ValueKey('picks-loading'),
          message: l10n.picksLoading,
          art: MevoraArt.searching,
        ),
        PicksPhase.error => MevoraErrorView(
          key: const ValueKey('picks-error'),
          title: l10n.picksLoadErrorTitle,
          message: state.errorMessage == null
              ? l10n.discoveryLoadErrorMessage
              : L10nErrors.message(l10n, state.errorMessage),
          onRetry: () => unawaited(widget.controller.load()),
        ),
        PicksPhase.loaded => _loaded(context, state),
      },
    );
  }

  Widget? _learningCard(MevoraPicksBatch batch) {
    final open = widget.onOpenLearning;
    if (open == null || !learningPromptVisible(batch.learning)) {
      return null;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        0,
        AppSpacing.screenPadding,
        AppSpacing.lg,
      ),
      child: LearningPromptCard(
        summary: batch.learning,
        onOpen: () => open(batch.learning),
        onSkipToday: widget.onSkipLearningToday == null
            ? null
            : () => widget.onSkipLearningToday!(batch.learning),
      ),
    );
  }

  Widget _loaded(BuildContext context, MevoraPicksState state) {
    final batch = state.batch;
    final open = widget.onOpenLearning;
    if (batch.emptyReason == PicksEmptyReason.learningRequired &&
        open != null) {
      return RefreshIndicator(
        key: const ValueKey('picks-learning-gate'),
        onRefresh: widget.controller.load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: LearningGate(
                summary: batch.learning,
                onOpen: () => open(batch.learning),
              ),
            ),
          ],
        ),
      );
    }
    final card = _learningCard(batch);
    return RefreshIndicator(
      key: const ValueKey('picks-loaded'),
      onRefresh: widget.controller.load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (batch.picks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                children: [
                  Expanded(child: _empty(context, batch)),
                  ?card,
                ],
              ),
            )
          else ...[
            SliverToBoxAdapter(child: _PicksHeader(batch: batch)),
            if (card != null) SliverToBoxAdapter(child: card),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding,
              ),
              sliver: SliverList.builder(
                itemCount: batch.picks.length,
                itemBuilder: (context, index) {
                  final pick = batch.picks[index];
                  return _PickEntry(
                    key: ValueKey(pick.uid),
                    index: index,
                    departing: state.departingUids.contains(pick.uid),
                    onShown: () => widget.controller.recordImpression(pick),
                    child: PickCard(
                      pick: pick,
                      busy:
                          state.pendingUids.contains(pick.uid) ||
                          state.departingUids.contains(pick.uid),
                      onOpen: () => widget.onOpenProfile(pick),
                      onLike: () => unawaited(widget.controller.like(pick)),
                      onPass: () => unawaited(widget.controller.pass(pick)),
                    ),
                  );
                },
              ),
            ),
            if (widget.footer != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  0,
                  AppSpacing.screenPadding,
                  AppSpacing.md,
                ),
                sliver: SliverToBoxAdapter(child: widget.footer),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
          ],
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, MevoraPicksBatch batch) {
    final l10n = AppLocalizations.of(context);
    if (batch.emptyReason == PicksEmptyReason.discoveryDisabled) {
      return MevoraEmptyState(
        art: MevoraArt.generic,
        title: l10n.picksDiscoveryOffTitle,
        message: l10n.picksDiscoveryOffMessage,
        actionLabel: widget.onOpenSettings == null ? null : l10n.settings,
        onAction: widget.onOpenSettings,
      );
    }
    // Today's set is finite: an intentional ending, never a refill.
    final done = batch.emptyReason == PicksEmptyReason.allDecided;
    widget.controller.analytics.exhausted(done ? 'allDecided' : 'noCandidates');
    return MevoraEmptyState(
      key: Key(done ? 'picksExhausted' : 'picksNoCandidates'),
      art: done ? MevoraArt.success : MevoraArt.emptyProfiles,
      title: done ? l10n.picksEmptyDoneTitle : l10n.picksEmptyPreparingTitle,
      message: done
          ? l10n.picksEmptyDoneMessage
          : l10n.picksEmptyNoCandidatesMessage,
    );
  }
}

class _PicksHeader extends StatelessWidget {
  const _PicksHeader({required this.batch});

  final MevoraPicksBatch batch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final count = batch.picks.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.sm,
        AppSpacing.screenPadding,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.picksHeadline,
              // The app bar already sets "Mevora Picks" in the display face;
              // a sans title keeps two serif headlines from stacking.
              style: theme.textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(l10n.picksIntroCount(count), style: theme.textTheme.bodyLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            batch.status == PicksStatus.lowSupply
                ? l10n.picksLowSupplyNote(count)
                : l10n.picksIntroNote,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Fades a card in on first appearance and folds it away once decided.
class _PickEntry extends StatefulWidget {
  const _PickEntry({
    super.key,
    required this.index,
    required this.departing,
    required this.onShown,
    required this.child,
  });

  final int index;
  final bool departing;
  final VoidCallback onShown;
  final Widget child;

  @override
  State<_PickEntry> createState() => _PickEntryState();
}

class _PickEntryState extends State<_PickEntry> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.onShown();
    // A short stagger so a fresh batch arrives card by card, not all at once.
    final delay = Duration(milliseconds: 60 * widget.index.clamp(0, 5));
    Future<void>.delayed(delay, () {
      if (mounted) {
        setState(() => _visible = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown = _visible && !widget.departing;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration = still ? Duration.zero : AppDurations.normal;
    return AnimatedSize(
      duration: duration,
      curve: AppCurves.standard,
      alignment: Alignment.topCenter,
      child: widget.departing
          ? const SizedBox(width: double.infinity)
          : AnimatedOpacity(
              duration: duration,
              opacity: shown ? 1 : 0,
              child: AnimatedSlide(
                duration: duration,
                curve: AppCurves.enter,
                offset: shown ? Offset.zero : const Offset(0, 0.04),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  child: widget.child,
                ),
              ),
            ),
    );
  }
}
