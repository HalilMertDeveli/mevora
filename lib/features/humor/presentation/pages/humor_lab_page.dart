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
import 'package:mevora/features/humor/presentation/widgets/humor_milestone_sheet.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_profile_sheet.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_rating_bar.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_report_sheet.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_swipe_hints.dart';
import 'package:mevora/l10n/app_localizations.dart';
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
  var _bootstrapFailed = false;
  int? _lastHandledInteraction;
  final Set<String> _mediaErrorIds = <String>{};
  String _uid = '';

  @override
  void initState() {
    super.initState();
    _education = widget.educationStore ?? HumorEducationStore();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _uid = widget.uidOverride ?? AuthScope.maybeOf(context)?.user?.id ?? '';
    if (_controller != null) {
      return;
    }
    try {
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
    } catch (error, stack) {
      debugPrint('HumorLab attach failed: $error\n$stack');
      if (mounted) {
        setState(() {
          _bootstrapFailed = true;
          _checkingIntro = false;
        });
      }
    }
  }

  Future<void> _bootstrap(HumorController controller) async {
    try {
      final introSeen = await _education.isIntroSeen(_uid);
      final helpDismissed = await _education.isRatingHelpDismissed(_uid);
      if (!mounted) return;
      setState(() {
        _showIntro = !introSeen;
        _ratingHelpDismissed = helpDismissed;
        _checkingIntro = false;
        _bootstrapFailed = false;
      });
      if (_showIntro) {
        _log(AnalyticsEvents.humorIntroShown);
      }
      await controller.load();
    } catch (error, stack) {
      debugPrint('HumorLab bootstrap failed: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _checkingIntro = false;
        _bootstrapFailed = true;
      });
    }
  }

  void _attach(HumorController controller) {
    _controller = controller;
    final initial = controller.state.currentIndex.clamp(0, 1 << 20);
    _pageController = PageController(initialPage: initial);
    _lastSyncedIndex = controller.state.currentIndex;
    controller.addListener(_onControllerChanged);
  }

  void _log(String name, {Map<String, Object>? parameters}) {
    final analytics = BoostScope.maybeOf(context)?.analytics;
    if (analytics == null) return;
    unawaited(analytics.logEvent(name, parameters: parameters));
  }

  Future<void> _completeIntro() async {
    try {
      await _education.markIntroSeen(_uid);
      _log(AnalyticsEvents.humorIntroCompleted);
    } catch (error, stack) {
      debugPrint('HumorLab intro complete failed: $error\n$stack');
    }
    if (!mounted) return;
    setState(() => _showIntro = false);
  }

  Future<void> _openProfile() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.refreshProfile();
      if (!mounted) return;
      _log(AnalyticsEvents.humorProfileOpened);
      _log(AnalyticsEvents.humorWhyMatchViewed);
      await HumorProfileSheet.show(
        context,
        profile: controller.state.profile,
        analytics: (name) async => _log(name),
      );
    } catch (error, stack) {
      debugPrint('HumorLab profile failed: $error\n$stack');
    }
  }

  Future<void> _presentAdFlow() async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    try {
      if (!controller.state.isPremium) {
        final seen = await _education.isAdInfoSeen(_uid);
        if (!seen && mounted) {
          _log(AnalyticsEvents.humorAdInfoShown);
          final result = await HumorAdInfoSheet.show(context);
          await _education.markAdInfoSeen(_uid);
          _log(AnalyticsEvents.humorAdInfoDismissed);
          if (result == HumorAdInfoResult.openPremium) {
            // Premium screen opened; continue feed when still free.
          }
        }
      }
      if (!mounted) return;
      await controller.presentPendingAd(hostContext: context);
    } catch (error, stack) {
      debugPrint('HumorLab ad flow failed: $error\n$stack');
      // Soft-fail: unlock feed if ad path threw.
      if (!mounted) return;
      try {
        await controller.presentPendingAd(hostContext: context);
      } catch (_) {}
    }
  }

  Future<void> _handleEducationAfterRating() async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final count = controller.state.profile.interactionCount;
    if (_lastHandledInteraction == count) return;
    _lastHandledInteraction = count;
    final l10n = AppLocalizations.of(context);

    try {
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
    } catch (error, stack) {
      debugPrint('HumorLab education failed: $error\n$stack');
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

    if (page == null || !page.hasClients) {
      return;
    }
    final index = controller.state.currentIndex;
    if (index == _lastSyncedIndex) {
      return;
    }
    if (index < 0 || index >= controller.state.items.length) {
      return;
    }
    _lastSyncedIndex = index;
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
          .catchError((Object _) {})
          .whenComplete(() => _syncingPage = false),
    );
  }

  void _onMediaError(String contentId) {
    if (_mediaErrorIds.contains(contentId)) {
      return;
    }
    _mediaErrorIds.add(contentId);
    final controller = _controller;
    if (controller == null) {
      return;
    }
    unawaited(controller.skipBrokenMedia(contentId));
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

    if (_bootstrapFailed && controller == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.humorLabTitle)),
        body: MevoraErrorView(
          message: l10n.humorFeedError,
          onRetry: () {
            setState(() {
              _bootstrapFailed = false;
              _checkingIntro = true;
              _controller = null;
            });
          },
          retryLabel: l10n.humorTryAgain,
        ),
      );
    }

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
        body: MevoraLoading.page(message: l10n.humorLoadingFeed),
      );
    }

    if (_showIntro) {
      return AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return HumorIntroView(
            interactionCount: controller.state.profile.interactionCount,
            isPremium: controller.state.isPremium,
            onContinue: () => unawaited(_completeIntro()),
            onOpenInfo: () {
              _log(AnalyticsEvents.humorInfoOpened);
              unawaited(HumorInfoSheet.show(context));
            },
          );
        },
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
              IconButton(
                tooltip: l10n.humorInfoTooltip,
                onPressed: () {
                  _log(AnalyticsEvents.humorInfoOpened);
                  unawaited(HumorInfoSheet.show(context));
                },
                icon: const Icon(Icons.info_outline_rounded),
              ),
              if (!state.isPremium)
                IconButton(
                  tooltip: l10n.humorPremiumCardCta,
                  onPressed: () => context.push(AppRoutes.boost),
                  icon: const Icon(Icons.auto_awesome_outlined),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  child: Center(
                    child: Icon(
                      Icons.verified_rounded,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                  ),
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
                        if (result.isSuccess) {
                          _log(
                            AnalyticsEvents.humorContentReported,
                            parameters: {
                              'content_id': item.contentId,
                              'reason': reason,
                            },
                          );
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
                ? MevoraLoading.page(message: l10n.humorLoadingFeed)
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
                    onMediaError: _onMediaError,
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
    required this.onMediaError,
  });

  final HumorController controller;
  final PageController pageController;
  final bool Function() syncingPage;
  final bool showRatingHelp;
  final VoidCallback onDismissRatingHelp;
  final Future<void> Function(HumorRating rating) onRated;
  final ValueChanged<String> onMediaError;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = controller.state;
    final locked = state.adsBlocked;
    final short = MediaQuery.sizeOf(context).height < 700;
    final showProgress = state.profile.profileBuilding ||
        state.profile.interactionCount < 20;

    return Column(
      children: [
        if (showProgress)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              0,
              AppSpacing.screenPadding,
              AppSpacing.sm,
            ),
            child: HumorProgressBlock(
              interactionCount: state.profile.interactionCount,
              showHint: state.profile.profileBuilding,
            ),
          ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
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
                              unawaited(controller.rateSwipeUp());
                            } else if (dy > 400) {
                              unawaited(controller.rateSwipeDown());
                            }
                          },
                    onDoubleTap: locked ? null : controller.replayCurrent,
                    child: HumorContentPlayer(
                      content: item,
                      isActive: index == state.currentIndex && !locked,
                      replayToken: state.replayToken,
                      onMediaError: onMediaError,
                    ),
                  );
                },
              ),
              const Positioned(
                right: AppSpacing.sm,
                top: AppSpacing.sm,
                child: HumorSwipeHints(compact: true),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Theme.of(context)
                            .colorScheme
                            .scrim
                            .withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.screenPadding,
                        short ? AppSpacing.sm : AppSpacing.md,
                        AppSpacing.screenPadding,
                        short ? AppSpacing.sm : AppSpacing.md,
                      ),
                      child: Material(
                        color: Theme.of(context)
                            .colorScheme
                            .surface
                            .withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          child: HumorRatingBar(
                            selected: state.lastRated,
                            enabled: !locked,
                            subtitle:
                                showRatingHelp ? l10n.humorRatingHelp : null,
                            onDismissHelp:
                                showRatingHelp ? onDismissRatingHelp : null,
                            onRated: (HumorRating rating) {
                              unawaited(onRated(rating));
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (state.isLoadingMore)
                Positioned(
                  left: 0,
                  right: 0,
                  top: AppSpacing.sm,
                  child: Center(
                    child: MevoraLoading(message: l10n.humorLoadingMore),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
