import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/boost_scope.dart';
import 'package:mevora/core/di/humor_scope.dart';
import 'package:mevora/core/localization/l10n_errors.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/humor/domain/config/humor_ads_settings.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/domain/services/humor_ad_service.dart';
import 'package:mevora/features/humor/domain/services/humor_education_policy.dart';
import 'package:mevora/features/humor/domain/services/humor_education_store.dart';
import 'package:mevora/features/humor/presentation/controllers/humor_controller.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_ad_info_sheet.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_content_player.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_info_sheet.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_intro_view.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_learning_progress_banner.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_milestone_sheet.dart';
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
  const HumorLabPage({
    super.key,
    this.controller,
    this.educationStore,
    this.uidOverride,
  });

  final HumorController? controller;
  final HumorEducationStore? educationStore;

  /// Tests can inject a stable uid without AuthScope.
  final String? uidOverride;

  @override
  State<HumorLabPage> createState() => _HumorLabPageState();
}

class _HumorLabPageState extends State<HumorLabPage> {
  HumorController? _owned;
  HumorController? _controller;
  PageController? _pageController;
  late final HumorEducationStore _education;
  var _syncingPage = false;
  int _lastSyncedIndex = 0;
  var _presentingAd = false;
  var _checkingIntro = true;
  var _showIntro = false;
  var _ratingHelpDismissed = false;
  int? _lastHandledInteraction;
  String _uid = '';

  @override
  void initState() {
    super.initState();
    _education = widget.educationStore ?? HumorEducationStore();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _uid = widget.uidOverride ??
        AuthScope.maybeOf(context)?.user?.id ??
        '';
    if (_controller != null) {
      return;
    }
    final provided = widget.controller;
    if (provided != null) {
      _attach(provided);
      unawaited(_bootstrap(provided));
      return;
    }
    final scope = HumorScope.maybeScopeOf(context);
    final repository = scope?.repository;
    if (repository == null) {
      return;
    }
    final analytics = BoostScope.maybeOf(context)?.analytics;
    final owned = HumorController(
      repository: repository,
      analytics: analytics,
      adService: scope?.adService,
      adsSettings: scope?.adsSettings ?? HumorAdsSettings.defaults,
      subscriptionRepository: scope?.subscriptionRepository,
    );
    _owned = owned;
    _attach(owned);
    unawaited(_bootstrap(owned));
  }

  Future<void> _bootstrap(HumorController controller) async {
    final introSeen = await _education.isIntroSeen(_uid);
    final helpDismissed = await _education.isRatingHelpDismissed(_uid);
    if (!mounted) return;
    setState(() {
      _showIntro = !introSeen;
      _ratingHelpDismissed = helpDismissed;
      _checkingIntro = false;
    });
    if (_showIntro) {
      _log(AnalyticsEvents.humorIntroShown);
    }
    await controller.load();
  }

  void _attach(HumorController controller) {
    _controller = controller;
    _pageController = PageController(initialPage: controller.state.currentIndex);
    _lastSyncedIndex = controller.state.currentIndex;
    controller.addListener(_onControllerChanged);
  }

  void _log(String name, {Map<String, Object>? parameters}) {
    final analytics = BoostScope.maybeOf(context)?.analytics;
    if (analytics == null) return;
    unawaited(analytics.logEvent(name, parameters: parameters));
  }

  Future<void> _completeIntro() async {
    await _education.markIntroSeen(_uid);
    _log(AnalyticsEvents.humorIntroCompleted);
    if (!mounted) return;
    setState(() => _showIntro = false);
  }

  Future<void> _openProfile() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.refreshProfile();
    if (!mounted) return;
    _log(AnalyticsEvents.humorProfileOpened);
    _log(AnalyticsEvents.humorWhyMatchViewed);
    await HumorProfileSheet.show(
      context,
      profile: controller.state.profile,
      analytics: (name) async => _log(name),
    );
  }

  Future<void> _presentAdFlow() async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    if (!controller.state.isPremium) {
      final seen = await _education.isAdInfoSeen(_uid);
      if (!seen && mounted) {
        _log(AnalyticsEvents.humorAdInfoShown);
        final result = await HumorAdInfoSheet.show(context);
        await _education.markAdInfoSeen(_uid);
        _log(AnalyticsEvents.humorAdInfoDismissed);
        if (result == HumorAdInfoResult.openPremium) {
          // Premium screen opened; still continue ad flow if still free.
        }
      }
    }
    if (!mounted) return;
    await controller.presentPendingAd(hostContext: context);
  }

  Future<void> _handleEducationAfterRating() async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final count = controller.state.profile.interactionCount;
    if (_lastHandledInteraction == count) return;
    _lastHandledInteraction = count;
    final l10n = AppLocalizations.of(context);

    if (HumorEducationPolicy.isHintMilestone(count)) {
      final already = await _education.wasMilestoneShown(_uid, count);
      if (!already && mounted) {
        await _education.markMilestoneShown(_uid, count);
        final msg = HumorEducationPolicy.hintMessage(l10n, count);
        if (msg != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
          );
        }
      }
    }

    if (HumorEducationPolicy.isShapingMilestone(count)) {
      final already = await _education.wasMilestoneShown(
        _uid,
        HumorEducationPolicy.shapingMilestone,
      );
      if (!already && mounted) {
        await _education.markMilestoneShown(
          _uid,
          HumorEducationPolicy.shapingMilestone,
        );
        _log(
          AnalyticsEvents.humorProfileMilestoneReached,
          parameters: {'milestone': HumorEducationPolicy.shapingMilestone},
        );
        if (!mounted) return;
        final action = await HumorMilestoneSheet.show(
          context,
          title: l10n.humorMilestoneShapingTitle,
          body: l10n.humorMilestoneShapingBody,
          showViewProfile: true,
        );
        if (action == HumorMilestoneAction.openProfile && mounted) {
          await _openProfile();
        }
      }
    }

    if (HumorEducationPolicy.isProfileMilestone(count)) {
      final already = await _education.wasMilestoneShown(
        _uid,
        HumorEducationPolicy.profileMilestone,
      );
      if (!already && mounted) {
        await _education.markMilestoneShown(
          _uid,
          HumorEducationPolicy.profileMilestone,
        );
        _log(
          AnalyticsEvents.humorProfileMilestoneReached,
          parameters: {'milestone': HumorEducationPolicy.profileMilestone},
        );
        if (!mounted) return;
        final action = await HumorMilestoneSheet.show(
          context,
          title: l10n.humorMilestoneProfileTitle,
          body: l10n.humorMilestoneProfileBody,
          showViewProfile: true,
        );
        if (action == HumorMilestoneAction.openProfile && mounted) {
          await _openProfile();
        }
      }
    }

    if (mounted &&
        HumorEducationPolicy.shouldShowRatingHelp(
          interactionCount: count,
          dismissed: _ratingHelpDismissed,
        ) ==
            false &&
        !_ratingHelpDismissed &&
        count >= HumorEducationPolicy.ratingHelpAutoHideAfter) {
      await _education.markRatingHelpDismissed(_uid);
      setState(() => _ratingHelpDismissed = true);
    }
  }

  void _onControllerChanged() {
    final controller = _controller;
    final page = _pageController;
    if (controller == null || !mounted) {
      return;
    }

    if (controller.state.adPhase == HumorAdPhase.eligible && !_presentingAd) {
      _presentingAd = true;
      unawaited(
        _presentAdFlow().whenComplete(() {
          _presentingAd = false;
        }),
      );
    }

    final interactionCount = controller.state.profile.interactionCount;
    if (_lastHandledInteraction != interactionCount &&
        interactionCount > 0 &&
        !_showIntro) {
      unawaited(_handleEducationAfterRating());
    }

    if (page == null) {
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

    if (_checkingIntro) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.humorLabTitle)),
        body: MevoraLoading.page(
          message: l10n.humorLoadingFeed,
          asset: MevoraRiveAssets.empty,
        ),
      );
    }

    if (_showIntro) {
      return HumorIntroView(onContinue: () => unawaited(_completeIntro()));
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.humorLabTitle),
            actions: [
              IconButton(
                tooltip: l10n.humorInfoTooltip,
                onPressed: () {
                  _log(AnalyticsEvents.humorInfoOpened);
                  unawaited(HumorInfoSheet.show(context));
                },
                icon: const Icon(Icons.info_outline_rounded),
              ),
              if (state.canUndo)
                IconButton(
                  tooltip: l10n.humorUndoRating,
                  onPressed: state.adsBlocked
                      ? null
                      : () => unawaited(controller.undo()),
                  icon: const Icon(Icons.undo_rounded),
                ),
              IconButton(
                tooltip: l10n.humorProfileTitle,
                onPressed: () => unawaited(_openProfile()),
                icon: const Icon(Icons.insights_outlined),
              ),
              IconButton(
                tooltip: l10n.humorSaved,
                onPressed: state.adsBlocked
                    ? null
                    : () => unawaited(controller.saveCurrent()),
                icon: const Icon(Icons.bookmark_border_rounded),
              ),
              IconButton(
                tooltip: l10n.humorReport,
                onPressed: state.adsBlocked
                    ? null
                    : () async {
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
                    showRatingHelp: HumorEducationPolicy.shouldShowRatingHelp(
                      interactionCount: state.profile.interactionCount,
                      dismissed: _ratingHelpDismissed,
                    ),
                    onDismissRatingHelp: () async {
                      await _education.markRatingHelpDismissed(_uid);
                      if (mounted) {
                        setState(() => _ratingHelpDismissed = true);
                      }
                    },
                    onRated: (rating) async {
                      await controller.rate(rating);
                    },
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
    required this.showRatingHelp,
    required this.onDismissRatingHelp,
    required this.onRated,
  });

  final HumorController controller;
  final PageController pageController;
  final bool Function() syncingPage;
  final bool showRatingHelp;
  final VoidCallback onDismissRatingHelp;
  final Future<void> Function(HumorRating rating) onRated;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = controller.state;
    final theme = Theme.of(context);
    final locked = state.adsBlocked;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            0,
            AppSpacing.screenPadding,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.humorLabSubtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (state.isPremium)
                Text(
                  l10n.humorPremiumAdFree,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                )
              else
                TextButton(
                  onPressed: () => context.push(AppRoutes.boost),
                  child: Text(l10n.humorPremiumAdFree),
                ),
            ],
          ),
        ),
        HumorLearningProgressBanner(profile: state.profile),
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
                  physics: locked
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  itemCount: state.items.length,
                  onPageChanged: (index) {
                    if (syncingPage() || locked) {
                      return;
                    }
                    unawaited(controller.onPageChanged(index));
                  },
                  itemBuilder: (context, index) {
                    final item = state.items[index];
                    return GestureDetector(
                      onVerticalDragEnd: locked
                          ? null
                          : (details) {
                              final dy = details.primaryVelocity ?? 0;
                              if (dy < -400) {
                                unawaited(controller.rateSwipeUp().then((_) {
                                  // Education handled only for explicit bar rates;
                                  // swipe-up also rates — trigger via listener count.
                                }));
                              } else if (dy > 400) {
                                unawaited(controller.rateSwipeDown());
                              }
                            },
                      onDoubleTap: locked ? null : controller.replayCurrent,
                      child: HumorContentPlayer(
                        content: item,
                        isActive: index == state.currentIndex && !locked,
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
            enabled: !locked,
            subtitle: showRatingHelp ? l10n.humorRatingHelp : null,
            onDismissHelp: showRatingHelp ? onDismissRatingHelp : null,
            onRated: (HumorRating rating) {
              unawaited(onRated(rating));
            },
          ),
        ),
      ],
    );
  }
}
