import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/boost_scope.dart';
import 'package:mevora/core/di/humor_scope.dart';
import 'package:mevora/core/localization/l10n_errors.dart';
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
  PageController? _pageController;
  var _syncingPage = false;
  int _lastSyncedIndex = 0;

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
    _pageController = PageController(initialPage: controller.state.currentIndex);
    _lastSyncedIndex = controller.state.currentIndex;
    controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    final controller = _controller;
    final page = _pageController;
    if (controller == null || page == null || !mounted) {
      return;
    }
    final index = controller.state.currentIndex;
    if (index == _lastSyncedIndex) {
      return;
    }
    _lastSyncedIndex = index;
    if (!page.hasClients) {
      return;
    }
    if (page.page?.round() == index) {
      return;
    }
    _syncingPage = true;
    unawaited(
      page
          .animateToPage(
            index,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() => _syncingPage = false),
    );
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    _pageController?.dispose();
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = _controller;
    if (controller == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.humorLabTitle)),
        body: MevoraEmptyState(
          icon: Icons.theater_comedy_outlined,
          title: l10n.humorLabTitle,
          message: l10n.humorLabSubtitle,
        ),
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.humorLabTitle),
            actions: [
              if (state.canUndo)
                IconButton(
                  tooltip: l10n.humorUndoRating,
                  onPressed: () => unawaited(controller.undo()),
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
                tooltip: l10n.humorSaved,
                onPressed: () => unawaited(controller.saveCurrent()),
                icon: const Icon(Icons.bookmark_border_rounded),
              ),
              IconButton(
                tooltip: l10n.humorReport,
                onPressed: () async {
                  final item = controller.state.current;
                  if (item == null) {
                    return;
                  }
                  final reason = await HumorReportSheet.show(context);
                  if (reason == null || !context.mounted) {
                    return;
                  }
                  final repo = HumorScope.maybeOf(context);
                  if (repo == null) {
                    return;
                  }
                  final result = await repo.reportContent(
                    contentId: item.contentId,
                    reason: reason,
                  );
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        result.isError
                            ? l10n.humorFeedError
                            : l10n.humorReportSuccess,
                      ),
                    ),
                  );
                },
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
                ? MevoraEmptyState(
                    icon: Icons.theater_comedy_outlined,
                    title: l10n.humorLabTitle,
                    message: l10n.humorEmptyFeed,
                    actionLabel: l10n.humorTryAgain,
                    onAction: () => unawaited(controller.load()),
                  )
                : _HumorFeedBody(
                    controller: controller,
                    pageController: _pageController!,
                    syncingPage: () => _syncingPage,
                  ),
          ),
        );
      },
    );
  }
}

class _HumorFeedBody extends StatelessWidget {
  const _HumorFeedBody({
    required this.controller,
    required this.pageController,
    required this.syncingPage,
  });

  final HumorController controller;
  final PageController pageController;
  final bool Function() syncingPage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = controller.state;
    final theme = Theme.of(context);

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
                  controller: pageController,
                  scrollDirection: Axis.vertical,
                  itemCount: state.items.length,
                  onPageChanged: (index) {
                    if (syncingPage()) {
                      return;
                    }
                    unawaited(controller.onPageChanged(index));
                  },
                  itemBuilder: (context, index) {
                    final item = state.items[index];
                    return GestureDetector(
                      onVerticalDragEnd: (details) {
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
                const Positioned(
                  right: AppSpacing.sm,
                  top: AppSpacing.sm,
                  child: HumorSwipeHints(compact: true),
                ),
              ],
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
            selected: state.lastRated,
            onRated: (HumorRating rating) {
              unawaited(controller.rate(rating));
            },
          ),
        ),
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
