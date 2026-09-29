import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/boost_scope.dart';
import 'package:mevora/core/di/humor_scope.dart';
import 'package:mevora/core/localization/l10n_errors.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/humor/domain/entities/humor_daily_set.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/presentation/controllers/humor_daily_controller.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_content_player.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_rating_bar.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/art/mevora_spot.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

/// Which line of microcopy accompanies the item on screen.
enum HumorDailyHint {
  start,
  middle,
  end;

  /// The opening items get the welcome, the last three "a few more", and
  /// everything between "getting to know you".
  static HumorDailyHint of(int position, int total) {
    if (position <= 1) {
      return HumorDailyHint.start;
    }
    if (position > total - 3) {
      return HumorDailyHint.end;
    }
    if (position <= 3) {
      return HumorDailyHint.start;
    }
    return HumorDailyHint.middle;
  }

  String label(AppLocalizations l10n) => switch (this) {
    HumorDailyHint.start => l10n.humorDailyHintStart,
    HumorDailyHint.middle => l10n.humorDailyHintMiddle,
    HumorDailyHint.end => l10n.humorDailyHintEnd,
  };
}

/// "Bugünün Mizah Turu": today's items, one at a time, in the server's order,
/// resuming wherever the user left off. No category is ever shown while
/// rating, and there is no user skip — only "Next" on media that failed.
class HumorDailyPage extends StatefulWidget {
  const HumorDailyPage({super.key, this.controller});

  final HumorDailyController? controller;

  @override
  State<HumorDailyPage> createState() => _HumorDailyPageState();
}

class _HumorDailyPageState extends State<HumorDailyPage> {
  HumorDailyController? _owned;
  HumorDailyController? _controller;
  var _shownFailureId = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) {
      return;
    }
    final provided = widget.controller;
    if (provided != null) {
      _attach(provided);
      unawaited(provided.load());
      return;
    }
    final repository = HumorScope.maybeOf(context);
    if (repository == null) {
      return;
    }
    final owned = HumorDailyController(
      repository: repository,
      analytics: BoostScope.maybeOf(context)?.analytics,
    );
    _owned = owned;
    _attach(owned);
    unawaited(owned.load());
  }

  void _attach(HumorDailyController controller) {
    _controller = controller;
    _shownFailureId = controller.state.actionFailureId;
    controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null || !mounted) {
      return;
    }
    final state = controller.state;
    if (state.actionFailureId == _shownFailureId) {
      return;
    }
    _shownFailureId = state.actionFailureId;
    final failure = state.actionFailure;
    if (failure == null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(L10nErrors.failure(l10n, failure)),
          persist: false,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: l10n.humorTryAgain,
            onPressed: () => unawaited(controller.retryFailedAction()),
          ),
        ),
      );
  }

  bool _canPop() {
    final router = GoRouter.maybeOf(context);
    return router?.canPop() ?? Navigator.of(context).canPop();
  }

  /// Leaving mid-tour is always fine: the server keeps the progress.
  void _close() {
    final router = GoRouter.maybeOf(context);
    if (router == null) {
      unawaited(Navigator.of(context).maybePop());
      return;
    }
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(AppRoutes.discovery);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = _controller;
    final canPop = _canPop();
    final leading = IconButton(
      tooltip: canPop
          ? MaterialLocalizations.of(context).backButtonTooltip
          : l10n.close,
      onPressed: _close,
      icon: canPop ? const BackButtonIcon() : const Icon(MevoraIcons.close),
    );
    if (controller == null) {
      return Scaffold(
        appBar: AppBar(leading: leading, title: Text(l10n.humorDailyTitle)),
        body: _calm(
          title: l10n.humorDailyNotReadyTitle,
          message: l10n.humorDailyNotReadyBody,
        ),
      );
    }
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _close();
        }
      },
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final state = controller.state;
          final set = state.set;
          final playing = state.current != null;
          return Scaffold(
            appBar: AppBar(
              leading: leading,
              title: Text(l10n.humorDailyTitle),
              bottom: playing && set != null && set.total > 0
                  ? PreferredSize(
                      preferredSize: const Size.fromHeight(4),
                      child: LinearProgressIndicator(
                        value: set.answeredCount / set.total,
                        minHeight: 4,
                      ),
                    )
                  : null,
            ),
            body: SafeArea(child: _body(l10n, controller)),
          );
        },
      ),
    );
  }

  Widget _body(AppLocalizations l10n, HumorDailyController controller) {
    final state = controller.state;
    final set = state.set;
    if (state.isLoading) {
      return MevoraLoading.page(
        message: l10n.humorLoadingFeed,
        art: MevoraArt.humor,
      );
    }
    if (state.failure != null || set == null) {
      final failure = state.failure;
      return MevoraErrorView(
        message: failure == null
            ? l10n.humorFeedError
            : L10nErrors.failure(l10n, failure),
        onRetry: () => unawaited(controller.load()),
        retryLabel: l10n.humorTryAgain,
      );
    }
    if (set.isLocked) {
      return _calm(
        title: l10n.humorDailyTitle,
        message: set.startsTomorrow
            ? l10n.humorDailyStartsTomorrow
            : l10n.humorDailyLockedBody,
      );
    }
    if (state.completed) {
      return MevoraEmptyState(
        art: MevoraArt.success,
        title: l10n.humorDailyCompletedTitle,
        message: l10n.humorDailyCompletedBody,
        actionLabel: l10n.close,
        onAction: _close,
      );
    }
    final item = state.current;
    if (item == null) {
      // Not ready yet (or a set with nothing playable): calm, never filler.
      return _calm(
        title: l10n.humorDailyNotReadyTitle,
        message: l10n.humorDailyNotReadyBody,
      );
    }
    return _DailyTour(controller: controller, set: set);
  }

  Widget _calm({required String title, required String message}) {
    return MevoraEmptyState(
      art: MevoraArt.humor,
      title: title,
      message: message,
      actionLabel: AppLocalizations.of(context).close,
      onAction: _close,
    );
  }
}

class _DailyTour extends StatelessWidget {
  const _DailyTour({required this.controller, required this.set});

  final HumorDailyController controller;
  final HumorDailySet set;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = controller.state;
    final item = state.current!;
    final position = state.position;
    final total = set.total;
    final progress = l10n.humorDailyProgress(position, total);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.sm,
            AppSpacing.screenPadding,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  HumorDailyHint.of(position, total).label(l10n),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Semantics(
                label: progress,
                child: Text(progress, style: theme.textTheme.labelLarge),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.card),
              child: HumorContentPlayer(
                // A fresh player per slot: nothing of the last item lingers.
                key: ValueKey('${set.dayId}:${state.currentIndex}'),
                content: item,
                analytics: controller.analytics,
                // A category hint while rating would steer the answer.
                showCategory: false,
                // The only skip in the tour: media that cannot be played is
                // passed server-side as `media_failed`.
                onSkipUnplayable: (contentId) =>
                    unawaited(controller.skipUnplayable(contentId)),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.md,
            AppSpacing.screenPadding,
            AppSpacing.md,
          ),
          child: HumorRatingBar(
            enabled: state.canAct,
            onRated: (HumorRating rating) => unawaited(controller.rate(rating)),
          ),
        ),
      ],
    );
  }
}
