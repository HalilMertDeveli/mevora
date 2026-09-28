import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/localization/l10n_format.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_decorations.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/theme/app_shadows.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_display_status.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_signal.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:mevora/features/discovery/presentation/controllers/discovery_controller.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_action_buttons.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_boost_badge.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_category_bar.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_network_image.dart';
import 'package:mevora/features/music/presentation/widgets/public_music_taste_section.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_question_answers_section.dart';
import 'package:mevora/features/relationship/presentation/widgets/relationship_compatibility_badge.dart';
import 'package:mevora/features/safety/presentation/widgets/discovery_safety_sheet.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';
import 'package:mevora/shared/widgets/mevora_icon_button.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';
import 'package:mevora/shared/widgets/mevora_section_header.dart';

/// A person, read like a short profile piece: portrait first, then who they
/// are, then *why they are here for you*, then their words, music and
/// answers. When opened from the deck, the pass / connect bar stays at hand
/// and the chosen action is returned to Discover.
class DiscoveryProfileDetailsPage extends StatefulWidget {
  const DiscoveryProfileDetailsPage({
    super.key,
    required this.candidate,
    this.controller,
    this.showActions = false,
  });

  final DiscoveryCandidate candidate;
  final DiscoveryController? controller;

  /// Show pass / priority / connect; the page pops with the chosen
  /// [DiscoveryDecision].
  final bool showActions;

  @override
  State<DiscoveryProfileDetailsPage> createState() =>
      _DiscoveryProfileDetailsPageState();
}

class _DiscoveryProfileDetailsPageState
    extends State<DiscoveryProfileDetailsPage> {
  final _scroll = ScrollController();
  double _photoHeight = 0;

  /// Once the portrait has scrolled away the chrome becomes a solid header,
  /// so the buttons never float over text.
  bool _solidHeader = false;

  void _onScroll() {
    final solid = _scroll.offset > _photoHeight - kToolbarHeight * 1.5;
    if (solid != _solidHeader) {
      setState(() => _solidHeader = solid);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    for (final url in widget.candidate.photos.take(4)) {
      DiscoveryNetworkImage.prefetch(url);
    }
  }

  void _openSafety() {
    final candidate = widget.candidate;
    unawaited(
      showDiscoverySafetySheet(
        context,
        userId: candidate.uid,
        onHide: widget.controller == null
            ? null
            : (userId) => widget.controller!.hideCandidate(userId),
        onBlocked: widget.controller == null
            ? null
            : (userId) => widget.controller!.hideCandidate(userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final candidate = widget.candidate;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = context.palette;
    final media = MediaQuery.sizeOf(context);
    final distance = candidate.distanceKm != null
        ? L10nFormat.distance(l10n, candidate.distanceKm!)
        : candidate.distanceLabel;
    final photoHeight = (media.width * 5 / 4).clamp(0.0, media.height * 0.62);
    final shared = candidate.sharedInterests.toSet();
    _photoHeight = photoHeight;
    final chromeVariant = _solidHeader
        ? MevoraIconButtonVariant.plain
        : MevoraIconButtonVariant.onMedia;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _solidHeader
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Stack(
          children: [
            CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: photoHeight,
                    child: _PhotoCarousel(photos: candidate.photos),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    AppSpacing.lg,
                    AppSpacing.screenPadding,
                    widget.showActions ? 128 : AppSpacing.xxl,
                  ),
                  sliver: SliverList.list(
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          '${candidate.displayName}, ${candidate.age}',
                          style: theme.textTheme.displaySmall,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s12),
                      Wrap(
                        spacing: AppSpacing.xs + 2,
                        runSpacing: AppSpacing.xs + 2,
                        children: [
                          if (candidate.isVerified)
                            MevoraPill(
                              label: l10n.profileVerifiedBadge,
                              icon: MevoraIcons.verified,
                              tone: MevoraTone.compatibility,
                            ),
                          if (candidate.isBoosted)
                            const DiscoveryBoostBadge(
                              compact: false,
                              onMedia: false,
                            ),
                          if (candidate.city != null &&
                              candidate.city!.isNotEmpty)
                            MevoraPill(
                              label: candidate.city!,
                              icon: MevoraIcons.location,
                            ),
                          if (distance != null && distance.isNotEmpty)
                            MevoraPill(label: distance),
                          if (candidate.relationshipGoal != null)
                            MevoraPill(
                              label: _relationshipLabel(
                                l10n,
                                candidate.relationshipGoal!,
                              ),
                              icon: MevoraIcons.like,
                            ),
                        ],
                      ),
                      if (_hasWhy(candidate)) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _WhyYouFitCard(candidate: candidate),
                      ],
                      if (candidate.bio != null &&
                          candidate.bio!.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xl),
                        MevoraSectionHeader(title: l10n.bio),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          candidate.bio!,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontSize: 17,
                            height: 26 / 17,
                          ),
                        ),
                      ],
                      // Renders nothing unless this member published a
                      // selection and left it visible.
                      if (candidate.publicMusic.hasContent) ...[
                        const SizedBox(height: AppSpacing.xl),
                        PublicMusicTasteSection(profile: candidate.publicMusic),
                      ],
                      if (candidate.interests.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xl),
                        MevoraSectionHeader(
                          title: l10n.interests,
                          subtitle: shared.isEmpty
                              ? null
                              : l10n.sharedHobbiesCount(shared.length),
                        ),
                        const SizedBox(height: AppSpacing.s12),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            // Shared interests first, drawn as selected.
                            for (final interest in [
                              ...candidate.interests.where(shared.contains),
                              ...candidate.interests.where(
                                (i) => !shared.contains(i),
                              ),
                            ])
                              MevoraChip(
                                label: interest,
                                selected: shared.contains(interest),
                                compact: true,
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      ProfileQuestionAnswersSection(uid: candidate.uid),
                    ],
                  ),
                ),
              ],
            ),
            // Floating chrome over the portrait; solid once it scrolls away.
            AnimatedContainer(
              duration: AppDurations.fast,
              curve: AppCurves.standard,
              decoration: BoxDecoration(
                color: _solidHeader
                    ? p.background
                    : p.background.withValues(alpha: 0),
                border: Border(
                  bottom: BorderSide(
                    color: _solidHeader ? p.divider : Colors.transparent,
                  ),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      MevoraIconButton(
                        icon: MevoraIcons.back,
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).backButtonTooltip,
                        variant: chromeVariant,
                        size: 44,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      Expanded(
                        child: AnimatedOpacity(
                          opacity: _solidHeader ? 1 : 0,
                          duration: AppDurations.fast,
                          child: ExcludeSemantics(
                            // The page heading already names the person.
                            child: Text(
                              '${candidate.displayName}, ${candidate.age}',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ),
                      ),
                      MevoraIconButton(
                        icon: MevoraIcons.more,
                        tooltip: l10n.more,
                        variant: chromeVariant,
                        size: 44,
                        onPressed: _openSafety,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.showActions) ...[
              // The fade is decoration only; it must not swallow scroll
              // gestures that start over it.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 160,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          p.background.withValues(alpha: 0),
                          p.background,
                        ],
                        stops: const [0, 0.55],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: DiscoveryActionButtons(
                      onPass: () =>
                          Navigator.of(context).pop(DiscoveryDecision.pass),
                      onSuperLike: () => Navigator.of(
                        context,
                      ).pop(DiscoveryDecision.superLike),
                      onLike: () =>
                          Navigator.of(context).pop(DiscoveryDecision.like),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _hasWhy(DiscoveryCandidate c) =>
      c.hasCompatibilityScore ||
      c.compatibilityStatus == CompatibilityDisplayStatus.calculating ||
      c.compatibilityReasons.isNotEmpty ||
      c.sharedInterests.isNotEmpty ||
      c.relationshipCompatibilityScore != null;

  String _relationshipLabel(AppLocalizations l10n, String goal) {
    return switch (goal) {
      'longTerm' => l10n.relationshipGoalLongTerm,
      'casual' => l10n.relationshipGoalCasual,
      'figuringOut' => l10n.relationshipGoalFiguringOut,
      _ => goal,
    };
  }
}

/// "Why you're seeing this": score ring, the signals, and the concrete
/// reasons — one sage card, so the reasoning reads as one thought.
class _WhyYouFitCard extends StatelessWidget {
  const _WhyYouFitCard({required this.candidate});

  final DiscoveryCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = context.palette;
    final signals = discoverySignals(candidate, limit: 4);
    final relationshipTopics = relationshipTopicsFromNames(
      candidate.relationshipSummaryTopics,
    );

    return MevoraCard(
      color: p.compatibilityContainer.withValues(alpha: 0.6),
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (candidate.hasCompatibilityScore) ...[
                CompatibilityRing(
                  score: candidate.compatibilityScore,
                  size: 56,
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.whyYoureSeeingThis,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (candidate.compatibilityStatus ==
                        CompatibilityDisplayStatus.calculating)
                      Text(
                        l10n.compatCalculating,
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (signals.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            CompatibilitySignalPills(signals: signals),
          ],
          if (candidate.compatibilityReasons.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            for (final reason in candidate.compatibilityReasons.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Icon(
                        MevoraIcons.check,
                        size: 16,
                        color: p.compatibility,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        reason,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontSize: 15,
                          height: 22 / 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (candidate.relationshipCompatibilityScore != null) ...[
            const SizedBox(height: AppSpacing.sm),
            RelationshipCompatibilityBadge(
              score: candidate.relationshipCompatibilityScore!,
              compact: false,
              showAccent: true,
            ),
            if (candidate.relationshipSharedViewCount != null ||
                relationshipTopics.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                [
                  if (candidate.relationshipSharedViewCount != null)
                    l10n.relationshipSharedViews(
                      candidate.relationshipSharedViewCount!,
                    ),
                  if (relationshipTopics.isNotEmpty)
                    relationshipTopicSummary(l10n, relationshipTopics),
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: p.onCompatibilityContainer,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Isolated carousel so photo index updates do not rebuild the details list
/// (match watchers / answer streams).
class _PhotoCarousel extends StatefulWidget {
  const _PhotoCarousel({required this.photos});

  final List<String> photos;

  @override
  State<_PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<_PhotoCarousel> {
  late final PageController _pageController = PageController();
  int _photoIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPhotoChanged(int index) {
    setState(() => _photoIndex = index);
    final photos = widget.photos;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (MediaQuery.sizeOf(context).width * dpr).round().clamp(
      320,
      1080,
    );
    if (index + 1 < photos.length) {
      DiscoveryNetworkImage.prefetch(photos[index + 1], cacheWidth: cacheWidth);
    }
    if (index > 0) {
      DiscoveryNetworkImage.prefetch(photos[index - 1], cacheWidth: cacheWidth);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final photos = widget.photos;
    final top = MediaQuery.paddingOf(context).top;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(AppRadii.card),
      ),
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photos.isEmpty)
              const PhotoUnavailablePlaceholder()
            else
              PageView.builder(
                controller: _pageController,
                itemCount: photos.length,
                // Load neighbors only after swipe; preloading full pending
                // Storage JPGs hangs the carousel on flaky networks.
                allowImplicitScrolling: false,
                onPageChanged: _onPhotoChanged,
                itemBuilder: (context, index) =>
                    DiscoveryNetworkImage(url: photos[index]),
              ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppDecorations.photoScrim(strength: 0.5),
                ),
              ),
            ),
            if (photos.length > 1)
              Positioned(
                top: top + 56,
                left: AppSpacing.md,
                right: AppSpacing.md,
                child: Semantics(
                  label: l10n.photoCounter(_photoIndex + 1, photos.length),
                  child: Row(
                    children: [
                      for (var i = 0; i < photos.length; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 3,
                            decoration: BoxDecoration(
                              color: i == _photoIndex
                                  ? AppColors.onMedia
                                  : AppColors.onMedia.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: AppShadows.card(Brightness.light),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
