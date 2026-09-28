import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/localization/l10n_errors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/picks/domain/entities/mevora_pick.dart';
import 'package:mevora/features/picks/presentation/controllers/mevora_picks_controller.dart';
import 'package:mevora/features/picks/presentation/widgets/pick_card.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

/// The Mevora Picks screen body: a short, explained list of people Mevora
/// chose, then a quiet way to browse more.
class PicksView extends StatefulWidget {
  const PicksView({
    super.key,
    required this.controller,
    required this.onOpenProfile,
    required this.onDiscoverMore,
    this.onOpenSettings,
    this.footer,
  });

  final MevoraPicksController controller;
  final void Function(MevoraPick pick) onOpenProfile;
  final VoidCallback onDiscoverMore;
  final VoidCallback? onOpenSettings;

  /// Shown under the Picks, above Discover More (e.g. the Humor Lab entry,
  /// whose calibration is what makes a Humor Match possible).
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
      duration: AppDurations.medium,
      child: switch (state.phase) {
        PicksPhase.initial || PicksPhase.loading => MevoraLoading.page(
          key: const ValueKey('picks-loading'),
          message: l10n.picksLoading,
          asset: MevoraRiveAssets.loading,
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

  Widget _loaded(BuildContext context, MevoraPicksState state) {
    final batch = state.batch;
    return RefreshIndicator(
      key: const ValueKey('picks-loaded'),
      onRefresh: widget.controller.load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (batch.picks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _empty(context, batch),
            )
          else ...[
            SliverToBoxAdapter(child: _PicksHeader(batch: batch)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
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
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                sliver: SliverToBoxAdapter(child: widget.footer),
              ),
            SliverToBoxAdapter(
              child: _DiscoverMoreFooter(onTap: widget.onDiscoverMore),
            ),
          ],
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, MevoraPicksBatch batch) {
    final l10n = AppLocalizations.of(context);
    if (batch.emptyReason == PicksEmptyReason.discoveryDisabled) {
      return MevoraEmptyState(
        icon: Icons.visibility_off_outlined,
        title: l10n.picksDiscoveryOffTitle,
        message: l10n.picksDiscoveryOffMessage,
        actionLabel: widget.onOpenSettings == null ? null : l10n.settings,
        onAction: widget.onOpenSettings,
      );
    }
    return MevoraEmptyState(
      icon: Icons.auto_awesome_outlined,
      riveAsset: MevoraRiveAssets.emptyProfiles,
      title: batch.emptyReason == PicksEmptyReason.allDecided
          ? l10n.picksEmptyDoneTitle
          : l10n.picksEmptyPreparingTitle,
      message: l10n.picksEmptyPreparingMessage,
      actionLabel: l10n.picksDiscoverMore,
      onAction: widget.onDiscoverMore,
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
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.picksHeadline,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(l10n.picksIntroCount(count), style: theme.textTheme.bodyLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            batch.status == PicksStatus.lowSupply
                ? l10n.picksLowSupplyNote(count)
                : l10n.picksIntroNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
    return AnimatedSize(
      duration: AppDurations.medium,
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: widget.departing
          ? const SizedBox(width: double.infinity)
          : AnimatedOpacity(
              duration: AppDurations.medium,
              opacity: shown ? 1 : 0,
              child: AnimatedSlide(
                duration: AppDurations.medium,
                curve: Curves.easeOutCubic,
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

class _DiscoverMoreFooter extends StatelessWidget {
  const _DiscoverMoreFooter({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Icon(Icons.explore_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.picksDiscoverMore,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.picksDiscoverMoreHint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
