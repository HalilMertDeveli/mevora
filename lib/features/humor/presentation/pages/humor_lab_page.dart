import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/boost_scope.dart';
import 'package:mevora/core/di/humor_scope.dart';
import 'package:mevora/core/localization/l10n_errors.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/presentation/controllers/humor_controller.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_content_player.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_profile_sheet.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_rating_bar.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_report_sheet.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_swipe_hints.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

class HumorLabPage extends StatefulWidget {
  const HumorLabPage({super.key, this.controller});

  final HumorController? controller;

  @override
  State<HumorLabPage> createState() => _HumorLabPageState();
}

class _HumorLabPageState extends State<HumorLabPage> {
  HumorController? _owned;
  HumorController? _controller;

  /// The last action failure already reported, so each one is shown once.
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
    final analytics = BoostScope.maybeOf(context)?.analytics;
    final owned = HumorController(repository: repository, analytics: analytics);
    _owned = owned;
    _attach(owned);
    unawaited(owned.load());
  }

  void _attach(HumorController controller) {
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
    if (state.calibrationJustCompleted) {
      // Only a rating the server reported as the one that finished
      // calibration earns the result screen. A user who was already
      // calibrated when the Lab opened is simply continuing to learn.
      controller.consumeCalibrationCompleted();
      final router = GoRouter.maybeOf(context);
      if (router == null) {
        unawaited(controller.loadMore());
      } else {
        unawaited(
          Future<void>.microtask(() {
            if (mounted) {
              router.go(AppRoutes.humorResult);
            }
          }),
        );
      }
    }
    if (state.actionFailureId != _shownFailureId) {
      _shownFailureId = state.actionFailureId;
      final failure = state.actionFailure;
      if (failure != null && state.items.isNotEmpty) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(L10nErrors.failure(l10n, failure)),
              action: SnackBarAction(
                label: l10n.humorTryAgain,
                onPressed: () => unawaited(controller.retryFailedAction()),
              ),
            ),
          );
      }
    }
  }

  bool _canPop() {
    final router = GoRouter.maybeOf(context);
    return router?.canPop() ?? Navigator.of(context).canPop();
  }

  /// Leaving is always possible: back to wherever the Lab was opened from,
  /// or to discovery when it was opened as the only screen.
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
      icon: canPop ? const BackButtonIcon() : const Icon(Icons.close_rounded),
    );

    if (controller == null) {
      return Scaffold(
        appBar: AppBar(leading: leading, title: Text(l10n.humorLabTitle)),
        body: MevoraEmptyState(
          icon: Icons.theater_comedy_outlined,
          title: l10n.humorLabTitle,
          message: l10n.humorLabSubtitle,
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
          final calibration = state.calibration;
          // Progress is only claimed once the server has said where the user
          // is — the placeholder state before the first load is not "0 / 15".
          final calibrating =
              !state.isLoading &&
              state.failure == null &&
              !calibration.complete &&
              calibration.totalCount > 0;
          final progressLabel = l10n.humorCalibrationProgress(
            calibration.completedCount,
            calibration.totalCount,
          );

          return Scaffold(
            appBar: AppBar(
              leading: leading,
              // While calibrating, the title *is* the progress: the user is
              // doing a finite thing and should be able to see the end of it.
              // Stage names stay internal — "anchor" means nothing to a person.
              title: Text(calibrating ? progressLabel : l10n.humorLabTitle),
              bottom: calibrating
                  ? PreferredSize(
                      preferredSize: const Size.fromHeight(4),
                      child: Semantics(
                        label: progressLabel,
                        value: '${(calibration.progress * 100).round()}%',
                        child: LinearProgressIndicator(
                          value: calibration.progress,
                          minHeight: 4,
                        ),
                      ),
                    )
                  : null,
              actions: [
                if (state.canGoBack)
                  IconButton(
                    tooltip: l10n.humorUndoRating,
                    onPressed: state.isSubmitting ? null : controller.goBack,
                    icon: const Icon(Icons.undo_rounded),
                  ),
                IconButton(
                  tooltip: l10n.humorProfileTitle,
                  onPressed: () async {
                    await controller.refreshProfile();
                    if (!context.mounted) {
                      return;
                    }
                    await HumorProfileSheet.show(
                      context,
                      profile: controller.state.profile,
                    );
                  },
                  icon: const Icon(Icons.insights_outlined),
                ),
                IconButton(
                  tooltip: l10n.humorReport,
                  onPressed: state.canAct
                      ? () => unawaited(_report(context, controller))
                      : null,
                  icon: const Icon(Icons.flag_outlined),
                ),
              ],
            ),
            body: SafeArea(
              child: state.isLoading
                  ? MevoraLoading.page(
                      message: l10n.humorLoadingFeed,
                      asset: MevoraRiveAssets.empty,
                    )
                  : state.failure != null && state.items.isEmpty
                  ? MevoraErrorView(
                      message: L10nErrors.failure(l10n, state.failure!),
                      onRetry: () => unawaited(controller.load()),
                      retryLabel: l10n.humorTryAgain,
                    )
                  : state.isEmpty
                  ? _HumorFeedEnd(
                      state: state,
                      onRetry: () => unawaited(controller.load()),
                    )
                  : _HumorFeedBody(controller: controller),
            ),
          );
        },
      ),
    );
  }

  Future<void> _report(BuildContext context, HumorController controller) async {
    final l10n = AppLocalizations.of(context);
    final reason = await HumorReportSheet.show(context);
    if (reason == null || !context.mounted) {
      return;
    }
    final result = await controller.reportCurrent(reason);
    // A failure is reported (with a retry) through the controller.
    if (result == null || result.isError || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.humorReportSuccess)));
  }
}

/// "Nothing (more) to show", in the three ways it can be true.
class _HumorFeedEnd extends StatelessWidget {
  const _HumorFeedEnd({required this.state, required this.onRetry});

  final HumorViewState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MevoraEmptyState(
      icon: state.catalogExhausted
          ? Icons.check_circle_outline
          : Icons.theater_comedy_outlined,
      title: l10n.humorLabTitle,
      // "You have seen everything" is an achievement, "there is nothing here"
      // is our problem, and a plain empty feed is worth retrying. Saying the
      // same thing to all three either blames the user or hides an outage.
      message: state.catalogExhausted
          ? l10n.humorFeedAllCaughtUp
          : state.catalogEmpty
          ? l10n.humorFeedNoContent
          : l10n.humorEmptyFeed,
      actionLabel: l10n.humorTryAgain,
      onAction: onRetry,
    );
  }
}

class _HumorFeedBody extends StatefulWidget {
  const _HumorFeedBody({required this.controller});

  final HumorController controller;

  @override
  State<_HumorFeedBody> createState() => _HumorFeedBodyState();
}

class _HumorFeedBodyState extends State<_HumorFeedBody> {
  late final PageController _pageController;
  var _syncScheduled = false;
  var _syncingPage = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: widget.controller.state.currentIndex,
    );
    widget.controller.addListener(_scheduleSync);
  }

  @override
  void didUpdateWidget(covariant _HumorFeedBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleSync);
      widget.controller.addListener(_scheduleSync);
      _scheduleSync();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scheduleSync);
    _pageController.dispose();
    super.dispose();
  }

  /// Follow the controller's index after the frame that lays out the new
  /// item count — animating before it would stop at the old last page.
  void _scheduleSync() {
    if (_syncScheduled || !mounted) {
      return;
    }
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      _syncPage();
    });
  }

  void _syncPage() {
    if (!mounted || !_pageController.hasClients) {
      return;
    }
    final target = widget.controller.state.currentIndex;
    final shown = _pageController.page?.round();
    if (shown == null || shown == target) {
      return;
    }
    _syncingPage = true;
    unawaited(
      _pageController
          .animateToPage(
            target,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() => _syncingPage = false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = widget.controller;
    final state = controller.state;
    final theme = Theme.of(context);
    final canAct = state.canAct;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            0,
            AppSpacing.screenPadding,
            AppSpacing.sm,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.humorLabSubtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding,
            ),
            child: Stack(
              children: [
                PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  // One extra slot past the last card while the user waits
                  // for the next page (or has reached the end), so the next
                  // card lands in place without a jump.
                  itemCount: state.items.length + (state.atTail ? 1 : 0),
                  onPageChanged: (index) {
                    if (_syncingPage) {
                      return;
                    }
                    unawaited(controller.onPageChanged(index));
                  },
                  itemBuilder: (context, index) {
                    if (index >= state.items.length) {
                      return _HumorTail(controller: controller);
                    }
                    final item = state.items[index];
                    return GestureDetector(
                      onVerticalDragEnd: (details) {
                        if (!controller.state.canAct) {
                          return;
                        }
                        final dy = details.primaryVelocity ?? 0;
                        if (dy < -400) {
                          unawaited(controller.rateSwipeUp());
                        } else if (dy > 400) {
                          unawaited(controller.rateSwipeDown());
                        }
                      },
                      onDoubleTap: controller.replayCurrent,
                      child: HumorContentPlayer(
                        content: item,
                        isActive: index == state.currentIndex,
                        replayToken: state.replayToken,
                      ),
                    );
                  },
                ),
                if (state.current != null)
                  const Positioned(
                    right: AppSpacing.sm,
                    top: AppSpacing.sm,
                    child: HumorSwipeHints(compact: true),
                  ),
              ],
            ),
          ),
        ),
        if (!state.reachedEnd) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.md,
              AppSpacing.screenPadding,
              0,
            ),
            child: HumorRatingBar(
              selected: state.lastRated,
              enabled: canAct,
              onRated: (HumorRating rating) {
                unawaited(controller.rate(rating));
              },
            ),
          ),
          TextButton.icon(
            onPressed: canAct ? () => unawaited(controller.skip()) : null,
            icon: const Icon(Icons.skip_next_rounded),
            label: Text(l10n.humorSkipContent),
          ),
        ],
        if (state.profile.profileBuilding)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              l10n.humorProfileBuilding,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// The slot after the last loaded card: the next page loading, a failed load
/// with a retry, or the end of what there is to show.
class _HumorTail extends StatelessWidget {
  const _HumorTail({required this.controller});

  final HumorController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = controller.state;
    if (state.reachedEnd) {
      return _HumorFeedEnd(
        state: state,
        onRetry: () => unawaited(controller.loadMore()),
      );
    }
    if (state.loadMoreFailed) {
      final failure = state.actionFailure;
      return MevoraErrorView(
        message: failure == null
            ? l10n.humorFeedError
            : L10nErrors.failure(l10n, failure),
        onRetry: () => unawaited(controller.loadMore()),
        retryLabel: l10n.humorTryAgain,
      );
    }
    return Center(child: MevoraLoading(message: l10n.humorLoadingFeed));
  }
}
