import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
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
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:mevora/features/discovery/presentation/controllers/discovery_controller.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_profile_card.dart';
import 'package:mevora/features/location/presentation/screens/location_permission_screen.dart';
import 'package:mevora/shared/animations/mevora_discovery_card_motion.dart';
import 'package:mevora/shared/animations/mevora_like_burst.dart';
import 'package:mevora/shared/animations/mevora_match_celebration.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';
import 'package:mevora/l10n/app_localizations.dart';

class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({super.key, this.controller});

  final DiscoveryController? controller;

  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage> {
  DiscoveryController? _owned;
  Offset _drag = Offset.zero;

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
    }
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
        onCompleted: controller.clearMatch,
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
      return MevoraEmptyState(
        icon: Icons.favorite_outline_rounded,
        title: l10n.discoveryEmptyTitle,
        message: l10n.discoveryEmptyMessage,
        actionLabel: l10n.retry,
        onAction: () => unawaited(controller.refresh()),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    setState(() => _drag += details.delta);
                  },
                  onVerticalDragUpdate: (details) {
                    setState(() => _drag += details.delta);
                  },
                  onHorizontalDragEnd: (_) => unawaited(_finishDrag(controller)),
                  onVerticalDragEnd: (_) => unawaited(_finishDrag(controller)),
                  child: MevoraDiscoveryCardMotion(
                    dragOffset: _drag,
                    child: DiscoveryProfileCard(candidate: current),
                  ),
                ),
                MevoraLikeBurst(play: state.showLikeBurst),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: MevoraButton(
                  label: l10n.pass,
                  variant: MevoraButtonVariant.ghost,
                  onPressed: () => unawaited(
                    controller.decide(DiscoveryDecision.pass),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: MevoraButton(
                  label: l10n.superLike,
                  variant: MevoraButtonVariant.secondary,
                  onPressed: () => unawaited(
                    controller.decide(DiscoveryDecision.superLike),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: MevoraButton(
                  label: l10n.like,
                  onPressed: () => unawaited(
                    controller.decide(DiscoveryDecision.like),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _finishDrag(DiscoveryController controller) async {
    final dx = _drag.dx;
    final dy = _drag.dy;
    setState(() => _drag = Offset.zero);
    if (dy < -120) {
      await controller.decide(DiscoveryDecision.superLike);
    } else if (dx > 120) {
      await controller.decide(DiscoveryDecision.like);
    } else if (dx < -120) {
      await controller.decide(DiscoveryDecision.pass);
    }
  }
}
