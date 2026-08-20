import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/boost_scope.dart';
import 'package:mevora/core/di/discovery_scope.dart';
import 'package:mevora/core/di/location_scope.dart';
import 'package:mevora/core/localization/l10n_errors.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/testing/fake_location_repository.dart';
import 'package:mevora/features/boost/presentation/pages/boost_screen.dart';
import 'package:mevora/features/boost/presentation/widgets/boost_button.dart';
import 'package:mevora/features/discovery/data/repositories/in_memory_discovery_repository.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_radius.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:mevora/features/discovery/presentation/controllers/discovery_controller.dart';
import 'package:mevora/features/discovery/presentation/pages/discovery_profile_details_page.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_action_buttons.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_card_stack.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_filters_sheet.dart';
import 'package:mevora/features/location/presentation/screens/location_permission_screen.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_discovery_card_motion.dart';
import 'package:mevora/shared/animations/mevora_match_celebration.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({super.key, this.controller});

  final DiscoveryController? controller;

  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage> {
  DiscoveryController? _owned;
  Offset _drag = Offset.zero;
  DiscoverySwipeDirection _swipeDirection = DiscoverySwipeDirection.none;
  bool _animateOut = false;

  DiscoveryController? get _controller => widget.controller ?? _owned;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.controller != null || _owned != null) {
      return;
    }
    final auth = AuthScope.maybeOf(context);
    final uid = auth?.user?.id ?? 'local';
    _owned = DiscoveryController(
      uid: uid,
      locationRepository:
          LocationScope.maybeOf(context)?.repository ??
          FakeLocationRepository(),
      discoveryRepository:
          DiscoveryScope.maybeOf(context) ?? InMemoryDiscoveryRepository(),
      purchaseRepository: BoostScope.maybeOf(context)?.repository,
    )..addListener(_onController);
    unawaited(_owned!.start());
  }

  void _onController() {
    if (mounted) {
      setState(() {});
      _prefetchPhotos();
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
  void initState() {
    super.initState();
    widget.controller?.addListener(_onController);
    unawaited(widget.controller?.start());
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onController);
    _owned?.removeListener(_onController);
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final auth = AuthScope.maybeOf(context);
    final l10n = AppLocalizations.of(context);
    if (controller == null) {
      return const Scaffold(body: MevoraLoading.page());
    }
    final state = controller.state;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appName),
        actions: [
          IconButton(
            tooltip: l10n.discoveryFiltersTitle,
            onPressed: state.isLoading ? null : () => _openFilters(controller),
            icon: const Icon(Icons.tune_rounded),
          ),
          BoostButton(
            isActive: state.activeBoost != null,
            onPressed: () => unawaited(_openBoost(controller)),
          ),
          IconButton(
            tooltip: l10n.logOut,
            onPressed: auth == null || auth.isBusy
                ? null
                : () => unawaited(auth.signOut()),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(child: _body(controller, state)),
    );
  }

  Future<void> _openFilters(DiscoveryController controller) async {
    final filters = await DiscoveryFiltersSheet.show(
      context,
      initial: controller.state.filters,
    );
    if (filters != null) {
      controller.setFilters(filters);
    }
  }

  Future<void> _openBoost(DiscoveryController controller) async {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      await router.push(AppRoutes.boost);
    } else {
      final scope = BoostScope.maybeOf(context);
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
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
    if (state.matchedCandidate != null) {
      final match = state.matchedCandidate!;
      return MevoraMatchCelebration(
        leftName: l10n.you,
        rightName: match.displayName,
        rightImage: match.photoUrl == null ? null : NetworkImage(match.photoUrl!),
        onSendMessage: () {
          controller.clearMatch();
          context.go(AppRoutes.matches);
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

    if (state.phase == LocationPromptPhase.error && state.current == null) {
      return MevoraErrorView(
        title: l10n.locationUnavailableTitle,
        message: state.errorMessage == null
            ? l10n.locationTimeoutMessage
            : L10nErrors.message(l10n, state.errorMessage),
        onRetry: () => unawaited(controller.refresh()),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              Text(l10n.radius, style: Theme.of(context).textTheme.labelLarge),
              const Spacer(),
              DropdownButton<DiscoveryRadius>(
                value: state.radius,
                onChanged: state.isLoading
                    ? null
                    : (value) {
                        if (value != null) {
                          unawaited(controller.setRadius(value));
                        }
                      },
                items: [
                  for (final radius in DiscoveryRadius.selectable)
                    DropdownMenuItem(
                      value: radius,
                      child: Text(l10n.radiusKm(radius.kilometers)),
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(child: _deck(controller, state)),
      ],
    );
  }

  Widget _deck(DiscoveryController controller, DiscoveryFeedState state) {
    final l10n = AppLocalizations.of(context);
    if (state.isLoading && state.current == null) {
      return const MevoraLoading.page();
    }
    final current = state.current;
    if (current == null) {
      if (state.hasSeenEveryone) {
        return MevoraEmptyState(
          icon: Icons.explore_outlined,
          riveAsset: MevoraRiveAssets.emptyProfiles,
          title: l10n.discoverySeenEveryoneTitle,
          message: l10n.discoverySeenEveryoneMessage,
          actionLabel: l10n.exploreAgain,
          onAction: () => unawaited(controller.exploreAgain()),
          secondaryActionLabel:
              state.isMockMode ? l10n.restartDemo : null,
          onSecondaryAction: state.isMockMode
              ? () => unawaited(controller.restartDemo())
              : null,
        );
      }
      return MevoraEmptyState(
        icon: Icons.favorite_outline_rounded,
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
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          DiscoveryActionButtons(
            enabled: !busy,
            onPass: () => unawaited(_triggerAction(
              controller,
              DiscoveryDecision.pass,
            )),
            onSuperLike: () => unawaited(_triggerAction(
              controller,
              DiscoveryDecision.superLike,
            )),
            onLike: () => unawaited(_triggerAction(
              controller,
              DiscoveryDecision.like,
            )),
          ),
        ],
      ),
    );
  }

  Future<void> _openProfileDetails(DiscoveryCandidate candidate) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DiscoveryProfileDetailsPage(candidate: candidate),
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
}
