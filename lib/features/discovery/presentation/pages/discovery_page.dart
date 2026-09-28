import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/di/settings_scope.dart';
import 'package:mevora/core/services/profile/profile_update_notifier.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/features/compatibility/domain/services/compatibility_breakdown_mapper.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_ui.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/boost_scope.dart';
import 'package:mevora/core/di/discovery_scope.dart';
import 'package:mevora/core/di/location_scope.dart';
import 'package:mevora/core/di/relationship_scope.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/core/localization/l10n_errors.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/testing/fake_location_repository.dart';
import 'package:mevora/features/boost/presentation/pages/boost_screen.dart';
import 'package:mevora/features/boost/presentation/widgets/boost_button.dart';
import 'package:mevora/features/discovery/data/repositories/in_memory_discovery_repository.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:mevora/features/discovery/presentation/controllers/discovery_controller.dart';
import 'package:mevora/features/discovery/presentation/pages/discovery_profile_details_page.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_action_buttons.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_card_stack.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_filters_sheet.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_lab_discover_entry.dart';
import 'package:mevora/features/location/presentation/screens/location_permission_screen.dart';
import 'package:mevora/features/picks/data/picks_analytics.dart';
import 'package:mevora/features/picks/domain/entities/mevora_pick.dart';
import 'package:mevora/features/picks/domain/repositories/mevora_picks_repository.dart';
import 'package:mevora/features/picks/presentation/controllers/mevora_picks_controller.dart';
import 'package:mevora/features/picks/presentation/widgets/picks_view.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_question_answers_section.dart';
import 'package:mevora/features/relationship/presentation/widgets/relationship_question_card.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_discovery_card_motion.dart';
import 'package:mevora/shared/animations/mevora_match_celebration.dart';
import 'package:mevora/shared/animations/mevora_page_transitions.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

/// Which of the tab's two experiences is in front.
enum DiscoveryMode {
  /// Mevora Picks: a few people Mevora chose, each with its reasons. Default.
  picks,

  /// The open-ended Discover deck, one tap away from Picks.
  discoverMore,
}

class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({super.key, this.controller, this.picksController});

  final DiscoveryController? controller;

  /// Injected by tests. Otherwise created when the discovery repository can
  /// serve Picks; without one (demo or in-memory data) the tab is the deck.
  final MevoraPicksController? picksController;

  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage>
    with WidgetsBindingObserver {
  DiscoveryController? _owned;
  MevoraPicksController? _ownedPicks;
  DiscoveryMode _mode = DiscoveryMode.picks;
  bool _picksStarted = false;
  ProfileUpdateNotifier? _profileUpdates;
  Offset _drag = Offset.zero;
  DiscoverySwipeDirection _swipeDirection = DiscoverySwipeDirection.none;
  bool _animateOut = false;

  DiscoveryController? get _controller => widget.controller ?? _owned;
  MevoraPicksController? get _picks => widget.picksController ?? _ownedPicks;
  bool get _showingPicks => _picks != null && _mode == DiscoveryMode.picks;
  bool get _inDiscoverMore =>
      _picks != null && _mode == DiscoveryMode.discoverMore;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller?.addListener(_onController);
    widget.picksController?.addListener(_onPicks);
    unawaited(widget.controller?.start());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      RelationshipScope.controllerOf(context)?.recordDiscoveryActivity();
      _maybeStartPicks();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (_showingPicks) {
      // Revalidates the batch: anyone blocked, matched or gone since drops out.
      if (_picksStarted) {
        unawaited(_picks!.load());
      }
      return;
    }
    // Soft refresh after long idle — keep deck if already loaded.
    if (controller.state.hasDiscoveryError ||
        controller.state.candidates.isEmpty) {
      unawaited(controller.refresh());
    }
  }

  void _pulseRelationshipActivity() {
    RelationshipScope.controllerOf(context)?.recordDiscoveryActivity();
  }

  void _onProfileUpdated() {
    final controller = _controller;
    final uid = AuthScope.maybeOf(context)?.user?.id;
    if (controller == null || uid == null) {
      return;
    }
    if (_profileUpdates?.lastUpdatedUid == uid) {
      controller.onProfileUpdated();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final updates = SettingsScope.maybeOf(context)?.profileUpdates;
    if (_profileUpdates != updates) {
      _profileUpdates?.removeListener(_onProfileUpdated);
      _profileUpdates = updates;
      _profileUpdates?.addListener(_onProfileUpdated);
    }

    // Always read AuthScope so didChangeDependencies triggers on login/logout.
    final uid = AuthScope.maybeOf(context)?.user?.id ?? 'local';

    // If caller injects a controller (tests), we don't manage lifecycle.
    if (widget.controller != null) {
      return;
    }

    // Re-create the discovery controller on auth uid changes.
    // The controller keeps user-specific state (cursors/candidates/compat cache),
    // so it must not survive logout -> login.
    if (_owned != null && _owned!.uid != uid) {
      _owned!.removeListener(_onController);
      _owned!.dispose();
      _owned = null;
      _ownedPicks?.removeListener(_onPicks);
      _ownedPicks?.dispose();
      _ownedPicks = null;
      _picksStarted = false;
      _mode = DiscoveryMode.picks;
    }

    if (_owned == null) {
      // Resolve every scope dependency eagerly, while this context is still
      // valid. viewerProfileLoader is invoked later and asynchronously from
      // DiscoveryController._loadViewerProfile; reading `context` in there
      // throws "This widget has been unmounted" once the page is gone, which
      // is what logout and account deletion do mid-load.
      final settingsHub = SettingsScope.maybeOf(context)?.settingsHub;
      final discoveryRepository =
          DiscoveryScope.maybeOf(context) ?? InMemoryDiscoveryRepository();
      final picksRepository = discoveryRepository is MevoraPicksCapable
          ? (discoveryRepository as MevoraPicksCapable).picksRepository
          : null;
      if (picksRepository != null) {
        _ownedPicks = MevoraPicksController(
          repository: picksRepository,
          analytics: PicksAnalytics(BoostScope.maybeOf(context)?.analytics),
        )..addListener(_onPicks);
      }
      _owned = DiscoveryController(
        uid: uid,
        locationRepository:
            LocationScope.maybeOf(context)?.repository ??
            FakeLocationRepository(),
        discoveryRepository: discoveryRepository,
        purchaseRepository: BoostScope.maybeOf(context)?.repository,
        // With Picks in front, the deck loads only when Discover More opens.
        loadDeckOnStart: picksRepository == null,
        viewerProfileLoader: (viewerUid) async =>
            await settingsHub?.loadProfile(viewerUid),
      )..addListener(_onController);
      unawaited(_owned!.start());
    }
  }

  void _onController() {
    if (mounted) {
      setState(() {});
      _prefetchPhotos();
      _maybeStartPicks();
    }
  }

  void _onPicks() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Picks load once location onboarding is settled, so the server ranks
  /// with the member's current position rather than a stale one.
  void _maybeStartPicks() {
    final picks = _picks;
    final controller = _controller;
    if (picks == null || controller == null || _picksStarted) {
      return;
    }
    if (controller.state.phase == LocationPromptPhase.explanation ||
        controller.state.isLoading) {
      return;
    }
    _picksStarted = true;
    unawaited(picks.load());
  }

  void _openDiscoverMore() {
    _pulseRelationshipActivity();
    _picks?.analytics.discoverMoreOpened();
    setState(() => _mode = DiscoveryMode.discoverMore);
    unawaited(_controller?.ensureDeckLoaded());
  }

  void _backToPicks() {
    setState(() => _mode = DiscoveryMode.picks);
    if (_picksStarted) {
      unawaited(_picks?.load());
    }
  }

  void _prefetchPhotos() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    prefetchDiscoveryPhotos(controller.state.stackCandidates);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _profileUpdates?.removeListener(_onProfileUpdated);
    widget.controller?.removeListener(_onController);
    widget.picksController?.removeListener(_onPicks);
    _owned?.removeListener(_onController);
    _owned?.dispose();
    _ownedPicks?.removeListener(_onPicks);
    _ownedPicks?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final l10n = AppLocalizations.of(context);
    if (controller == null) {
      return const Scaffold(
        body: MevoraLoading.page(asset: MevoraRiveAssets.loading),
      );
    }
    final state = controller.state;
    final relationship = RelationshipScope.controllerOf(context);
    final matchCount =
        SocialScope.maybeOf(
          context,
        )?.matchesController.activeConversationCount ??
        0;
    // LazyShellNavigator disables TickerMode for offstage tabs. Discover stays
    // mounted after first visit — never report "visible" while offstage.
    final discoveryVisible = TickerMode.valuesOf(context).enabled;
    Widget body = SafeArea(child: _body(controller, state));
    if (relationship != null) {
      body = RelationshipPromptHost(
        controller: relationship,
        discoveryVisible: discoveryVisible,
        normalMatchCount: matchCount,
        child: body,
      );
    }
    final (title, subtitle) = _showingPicks
        ? (l10n.picksTitle, l10n.picksSubtitle)
        : _inDiscoverMore
        ? (l10n.picksDiscoverMore, l10n.discoverMoreSubtitle)
        : (l10n.discoverBestMatchesTitle, l10n.discoverBestMatchesSubtitle);
    return PopScope(
      // In Discover More, back returns to Picks instead of leaving the tab.
      canPop: !_inDiscoverMore,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _inDiscoverMore) {
          _backToPicks();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _inDiscoverMore
              ? IconButton(
                  tooltip: l10n.picksBackToPicks,
                  onPressed: _backToPicks,
                  icon: const Icon(Icons.arrow_back_rounded),
                )
              : null,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            // Filters shape the deck; Picks are chosen by compatibility.
            if (!_showingPicks)
              IconButton(
                tooltip: l10n.discoveryFiltersTitle,
                onPressed: state.isLoading
                    ? null
                    : () => _openFilters(controller),
                icon: const Icon(Icons.tune_rounded),
              ),
            BoostButton(
              isActive: state.activeBoost != null,
              onPressed: () => unawaited(_openBoost(controller)),
            ),
            IconButton(
              tooltip: l10n.settings,
              onPressed: () => context.push(AppRoutes.settings),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: body,
      ),
    );
  }

  Future<void> _openFilters(DiscoveryController controller) async {
    final filters = await DiscoveryFiltersSheet.show(
      context,
      initial: controller.state.filters,
    );
    if (filters != null) {
      unawaited(controller.setFilters(filters));
    }
  }

  Future<void> _openBoost(DiscoveryController controller) async {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      await router.push(AppRoutes.boost);
    } else {
      final scope = BoostScope.maybeOf(context);
      await Navigator.of(context).push<void>(
        MevoraPageTransitions.route<void>(
          builder: (_) => scope == null
              ? const BoostScreen()
              : BoostScope(
                  repository: scope.repository,
                  analytics: scope.analytics,
                  child: const BoostScreen(),
                ),
        ),
      );
    }
    await controller.refreshBoost();
  }

  Widget _body(DiscoveryController controller, DiscoveryFeedState state) {
    final l10n = AppLocalizations.of(context);
    final pickMatch = _picks?.state.matchedPick;
    if (pickMatch != null) {
      return _pickMatchCelebration(controller, pickMatch);
    }
    if (state.matchedCandidate != null) {
      final match = state.matchedCandidate!;
      final viewer = _viewerProfile(context);
      final breakdown = controller.breakdownFor(match);
      final reasons = CompatibilityBreakdownMapper.reasonsFor(
        viewer: viewer,
        candidate: match,
        breakdown: breakdown,
      );
      return MevoraMatchCelebration(
        leftName: l10n.you,
        rightName: match.displayName,
        rightImage: MevoraNetworkImages.provider(match.photoUrl),
        compatibilitySection: WhyYouMatchPanel(
          breakdown: breakdown,
          reasons: reasons,
        ),
        onSendMessage: () {
          final matchId = controller.state.matchedMatchId;
          controller.clearMatch();
          if (matchId != null && matchId.isNotEmpty) {
            unawaited(context.push(AppRoutes.chatPath(matchId)));
          } else {
            context.go(AppRoutes.matches);
          }
        },
        onViewAnswers: () {
          final otherUid = match.uid;
          controller.clearMatch();
          unawaited(
            showMatchedProfileAnswersSheet(context, otherUid: otherUid),
          );
        },
        onKeepExploring: controller.clearMatch,
      );
    }

    if (state.phase == LocationPromptPhase.explanation) {
      return LocationPermissionScreen(
        isBusy: state.isLoading,
        onUseLocation: () => unawaited(controller.useMyLocation()),
        onNotNow: () => unawaited(controller.skipLocation()),
      );
    }

    if (state.phase == LocationPromptPhase.permanentlyDenied) {
      return MevoraEmptyState(
        icon: Icons.lock_outline,
        title: l10n.locationSettingsTitle,
        message: l10n.locationSettingsMessage,
        actionLabel: l10n.openSettings,
        onAction: () => unawaited(controller.openSettings()),
      );
    }

    if (state.phase == LocationPromptPhase.gpsDisabled) {
      return MevoraEmptyState(
        icon: Icons.location_off_outlined,
        title: l10n.gpsDisabledTitle,
        message: l10n.gpsDisabledMessage,
        actionLabel: l10n.continueWithoutLocation,
        onAction: () => unawaited(controller.skipLocation()),
      );
    }

    if (_showingPicks) {
      return PicksView(
        controller: _picks!,
        onOpenProfile: _openPickProfile,
        onDiscoverMore: _openDiscoverMore,
        onOpenSettings: () => context.push(AppRoutes.settings),
        footer: const HumorLabDiscoverEntry(),
      );
    }

    if (state.hasDiscoveryError && state.current == null) {
      return MevoraErrorView(
        title: l10n.discoveryLoadErrorTitle,
        message: state.errorMessage == null
            ? l10n.discoveryLoadErrorMessage
            : L10nErrors.message(l10n, state.errorMessage),
        onRetry: () => unawaited(controller.refresh()),
      );
    }

    if (state.phase == LocationPromptPhase.error && state.current == null) {
      return MevoraErrorView(
        title: l10n.locationUnavailableTitle,
        message: state.errorMessage == null
            ? l10n.locationTimeoutMessage
            : L10nErrors.message(l10n, state.errorMessage),
        onRetry: () => unawaited(controller.refresh()),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      // An empty or seen-everyone deck is exactly when there is time for Humor
      // Lab, so its entry stays reachable there too.
      child: state.current == null && !state.isLoading
          ? _withHumorEntry(_deck(controller, state))
          : _deck(controller, state),
    );
  }

  Widget _withHumorEntry(Widget empty) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            0,
          ),
          child: HumorLabDiscoverEntry(),
        ),
        Expanded(child: empty),
      ],
    );
  }

  Widget _deck(DiscoveryController controller, DiscoveryFeedState state) {
    final l10n = AppLocalizations.of(context);
    if (state.isLoading && state.current == null) {
      return MevoraLoading.page(
        message: l10n.discoveryLoading,
        asset: MevoraRiveAssets.loading,
      );
    }
    final current = state.current;
    if (current == null) {
      if (state.hasSeenEveryone) {
        return MevoraEmptyState(
          icon: Icons.explore_outlined,
          riveAsset: MevoraRiveAssets.emptyProfiles,
          title: l10n.discoverySeenEveryoneTitle,
          message: l10n.discoverySeenEveryoneMessage,
          actionLabel: state.isMockMode ? l10n.restartDemo : l10n.exploreAgain,
          onAction: () => unawaited(
            state.isMockMode
                ? controller.restartDemo()
                : controller.exploreAgain(),
          ),
          secondaryActionLabel: l10n.discoveryChangePreferences,
          onSecondaryAction: () => unawaited(_openFilters(controller)),
        );
      }
      return MevoraEmptyState(
        icon: Icons.insights_outlined,
        riveAsset: MevoraRiveAssets.emptyProfiles,
        title: l10n.discoveryEmptyTitle,
        message: l10n.discoveryEmptyMessage,
        actionLabel: l10n.retry,
        onAction: () => unawaited(controller.refresh()),
      );
    }

    final busy = controller.isProcessingAction || _animateOut;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          const HumorLabDiscoverEntry(),
          if (state.hiddenCompatibility != null &&
              !state.hiddenCompatibilityDismissed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: HiddenCompatibilityCard(
                insight: state.hiddenCompatibility!,
                onDiscover: controller.focusHiddenCompatibility,
                onDismiss: controller.dismissHiddenCompatibility,
              ),
            ),
          Expanded(
            child: DiscoveryCardStack(
              candidates: state.stackCandidates,
              dragOffset: _drag,
              swipeDirection: _swipeDirection,
              animateOut: _animateOut,
              showLikeBurst: state.showLikeBurst,
              swipeThreshold: controller.swipeThreshold,
              onDragUpdate: (delta) {
                setState(() => _drag += delta);
              },
              onDragEnd: () => unawaited(_finishDrag(controller)),
              onCardTap: (candidate) => _openProfileDetails(candidate),
              onWhyTap: current.hasCompatibilityScore
                  ? () => _openCompatibility(context, current)
                  : null,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          DiscoveryActionButtons(
            enabled: !busy,
            onPass: () =>
                unawaited(_triggerAction(controller, DiscoveryDecision.pass)),
            onSuperLike: () => unawaited(
              _triggerAction(controller, DiscoveryDecision.superLike),
            ),
            onLike: () =>
                unawaited(_triggerAction(controller, DiscoveryDecision.like)),
          ),
        ],
      ),
    );
  }

  Widget _pickMatchCelebration(
    DiscoveryController controller,
    MevoraPick pick,
  ) {
    final l10n = AppLocalizations.of(context);
    final picks = _picks!;
    final match = pick.candidate;
    final breakdown = controller.breakdownFor(match);
    final reasons = CompatibilityBreakdownMapper.reasonsFor(
      viewer: _viewerProfile(context),
      candidate: match,
      breakdown: breakdown,
    );
    return MevoraMatchCelebration(
      leftName: l10n.you,
      rightName: match.displayName,
      rightImage: MevoraNetworkImages.provider(match.photoUrl),
      compatibilitySection: WhyYouMatchPanel(
        breakdown: breakdown,
        reasons: reasons,
      ),
      onSendMessage: () {
        final matchId = picks.state.matchedMatchId;
        picks.clearMatch();
        if (matchId != null && matchId.isNotEmpty) {
          unawaited(context.push(AppRoutes.chatPath(matchId)));
        } else {
          context.go(AppRoutes.matches);
        }
      },
      onViewAnswers: () {
        picks.clearMatch();
        unawaited(showMatchedProfileAnswersSheet(context, otherUid: match.uid));
      },
      onKeepExploring: picks.clearMatch,
    );
  }

  /// Opening a profile is not a decision: coming back leaves the Pick as it
  /// was. Only Like or Pass — here or on the profile — moves it.
  Future<void> _openPickProfile(MevoraPick pick) async {
    final picks = _picks;
    if (picks == null) {
      return;
    }
    _pulseRelationshipActivity();
    picks.recordProfileOpened(pick);
    final decision = await Navigator.of(context).push<DiscoveryDecision>(
      MevoraPageTransitions.route<DiscoveryDecision>(
        builder: (_) => DiscoveryProfileDetailsPage(
          candidate: pick.candidate,
          pick: pick,
          onHide: (userId) => picks.hide(userId),
          onBlocked: (userId) async => picks.removeImmediately(userId),
        ),
      ),
    );
    if (!mounted || decision == null) {
      return;
    }
    await switch (decision) {
      DiscoveryDecision.pass => picks.pass(pick),
      DiscoveryDecision.like || DiscoveryDecision.superLike => picks.like(pick),
    };
  }

  Future<void> _openProfileDetails(DiscoveryCandidate candidate) async {
    _pulseRelationshipActivity();
    await Navigator.of(context).push<void>(
      MevoraPageTransitions.route<void>(
        builder: (_) => DiscoveryProfileDetailsPage(
          candidate: candidate,
          controller: _controller,
        ),
      ),
    );
  }

  Future<void> _triggerAction(
    DiscoveryController controller,
    DiscoveryDecision decision,
  ) async {
    final current = controller.state.current;
    if (current == null || controller.isProcessingAction) {
      return;
    }
    _pulseRelationshipActivity();
    final direction = switch (decision) {
      DiscoveryDecision.like => DiscoverySwipeDirection.like,
      DiscoveryDecision.pass => DiscoverySwipeDirection.pass,
      DiscoveryDecision.superLike => DiscoverySwipeDirection.superLike,
    };
    setState(() {
      _swipeDirection = direction;
      _animateOut = true;
    });
    await Future<void>.delayed(AppDurations.discoveryCard);
    if (!mounted) {
      return;
    }
    setState(() {
      _drag = Offset.zero;
      _swipeDirection = DiscoverySwipeDirection.none;
      _animateOut = false;
    });
    await switch (decision) {
      DiscoveryDecision.like => controller.onLike(current.uid),
      DiscoveryDecision.pass => controller.onPass(current.uid),
      DiscoveryDecision.superLike => controller.onSuperLike(current.uid),
    };
  }

  Future<void> _finishDrag(DiscoveryController controller) async {
    final dx = _drag.dx;
    final dy = _drag.dy;
    final threshold = controller.swipeThreshold;
    DiscoveryDecision? decision;
    DiscoverySwipeDirection direction = DiscoverySwipeDirection.none;

    if (dy < -threshold && dy.abs() > dx.abs()) {
      decision = DiscoveryDecision.superLike;
      direction = DiscoverySwipeDirection.superLike;
    } else if (dx > threshold) {
      decision = DiscoveryDecision.like;
      direction = DiscoverySwipeDirection.like;
    } else if (dx < -threshold) {
      decision = DiscoveryDecision.pass;
      direction = DiscoverySwipeDirection.pass;
    }

    if (decision == null) {
      setState(() => _drag = Offset.zero);
      return;
    }

    _pulseRelationshipActivity();
    final current = controller.state.current;
    if (current == null) {
      setState(() => _drag = Offset.zero);
      return;
    }

    setState(() {
      _swipeDirection = direction;
      _animateOut = true;
    });
    await Future<void>.delayed(AppDurations.discoveryCard);
    if (!mounted) {
      return;
    }
    setState(() {
      _drag = Offset.zero;
      _swipeDirection = DiscoverySwipeDirection.none;
      _animateOut = false;
    });
    await switch (decision) {
      DiscoveryDecision.like => controller.onLike(current.uid),
      DiscoveryDecision.pass => controller.onPass(current.uid),
      DiscoveryDecision.superLike => controller.onSuperLike(current.uid),
    };
  }

  UserProfile _viewerProfile(BuildContext context) {
    final controller = _controller;
    if (controller?.viewerProfile != null) {
      return controller!.viewerProfile!;
    }
    final auth = AuthScope.maybeOf(context)?.user;
    return UserProfile(
      uid: auth?.id ?? 'self',
      displayName: auth?.displayName ?? 'You',
    );
  }

  Future<void> _openCompatibility(
    BuildContext context,
    DiscoveryCandidate candidate,
  ) async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final viewer = _viewerProfile(context);
    final breakdown = controller.breakdownFor(candidate);
    final reasons = CompatibilityBreakdownMapper.reasonsFor(
      viewer: viewer,
      candidate: candidate,
      breakdown: breakdown,
    );
    await showCompatibilityBreakdownSheet(
      context,
      breakdown: breakdown,
      reasons: reasons,
    );
  }
}
