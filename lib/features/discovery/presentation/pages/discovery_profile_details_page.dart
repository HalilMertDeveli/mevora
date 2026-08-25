import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/localization/l10n_format.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_discover_badge.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/presentation/controllers/discovery_controller.dart';
import 'package:mevora/features/safety/presentation/widgets/discovery_safety_sheet.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_boost_badge.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_network_image.dart';
import 'package:mevora/features/music/presentation/widgets/music_compatibility_badge.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_question_answers_section.dart';
import 'package:mevora/features/relationship/presentation/widgets/relationship_compatibility_badge.dart';
import 'package:mevora/features/verification/presentation/widgets/verified_profile_badge.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

class DiscoveryProfileDetailsPage extends StatefulWidget {
  const DiscoveryProfileDetailsPage({
    super.key,
    required this.candidate,
    this.controller,
  });

  final DiscoveryCandidate candidate;
  final DiscoveryController? controller;

  @override
  State<DiscoveryProfileDetailsPage> createState() =>
      _DiscoveryProfileDetailsPageState();
}

class _DiscoveryProfileDetailsPageState
    extends State<DiscoveryProfileDetailsPage> {
  @override
  void initState() {
    super.initState();
    for (final url in widget.candidate.photos.take(4)) {
      DiscoveryNetworkImage.prefetch(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidate = widget.candidate;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final distance = candidate.distanceKm != null
        ? L10nFormat.distance(l10n, candidate.distanceKm!)
        : candidate.distanceLabel;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileDetailsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz),
            tooltip: l10n.more,
            onPressed: () => showDiscoverySafetySheet(
              context,
              userId: candidate.uid,
              onHide: widget.controller == null
                  ? null
                  : (userId) => widget.controller!.hideCandidate(userId),
              onBlocked: widget.controller == null
                  ? null
                  : (userId) => widget.controller!.hideCandidate(userId),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                0,
              ),
              child: _DiscoveryPhotoCarousel(photos: candidate.photos),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  Text(
                    '${candidate.displayName}, ${candidate.age}',
                    style: theme.textTheme.headlineSmall,
                  ),
                  if (candidate.isVerified) ...[
                    const SizedBox(height: AppSpacing.xs),
                    const VerifiedProfileBadge(),
                  ],
                  if (candidate.isBoosted) ...[
                    const SizedBox(height: AppSpacing.xs),
                    const DiscoveryBoostBadge(compact: false),
                  ],
                  if (candidate.city != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      candidate.city!,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      if (distance != null && distance.isNotEmpty)
                        MevoraChip(label: distance, compact: true),
                      CompatibilityDiscoverBadge(
                        score: candidate.compatibilityScore,
                        status: candidate.compatibilityStatus,
                      ),
                      if (candidate.musicCompatibilityScore != null)
                        MusicCompatibilityBadge(
                          score: candidate.musicCompatibilityScore!,
                          sharedTracks: candidate.sharedMusicTracks,
                          sharedArtists: candidate.sharedMusicArtists,
                          sharedGenres: candidate.sharedMusicGenres,
                          insights: candidate.musicInsights,
                          sharedTrackCount: candidate.sharedMusicTrackCount,
                          sharedArtistCount: candidate.sharedMusicArtistCount,
                          sharedPlaylistTrackCount:
                              candidate.sharedMusicPlaylistTrackCount,
                        ),
                      if (candidate.relationshipCompatibilityScore != null)
                        RelationshipCompatibilityBadge(
                          score: candidate.relationshipCompatibilityScore!,
                          showAccent: true,
                        ),
                      if (candidate.relationshipGoal != null)
                        MevoraChip(
                          label: _relationshipLabel(
                            l10n,
                            candidate.relationshipGoal!,
                          ),
                          compact: true,
                        ),
                    ],
                  ),
                  if (candidate.bio != null && candidate.bio!.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(l10n.bio, style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(candidate.bio!, style: theme.textTheme.bodyLarge),
                  ],
                  if (candidate.interests.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(l10n.interests, style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: candidate.interests
                          .map((interest) => MevoraChip(label: interest))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  ProfileQuestionAnswersSection(uid: candidate.uid),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    l10n.whyYoureSeeingThis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (candidate.hasCompatibilityScore)
                    MevoraChip(
                      label: l10n.compatDiscoverBadge(
                        candidate.compatibilityScore,
                      ),
                      selected: true,
                    )
                  else
                    CompatibilityDiscoverBadge(
                      score: candidate.compatibilityScore,
                      status: candidate.compatibilityStatus,
                    ),
                  if (candidate.musicCompatibilityScore != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    MusicCompatibilityBadge(
                      score: candidate.musicCompatibilityScore!,
                      compact: false,
                      sharedTracks: candidate.sharedMusicTracks,
                      sharedArtists: candidate.sharedMusicArtists,
                      sharedGenres: candidate.sharedMusicGenres,
                      insights: candidate.musicInsights,
                      sharedTrackCount: candidate.sharedMusicTrackCount,
                      sharedArtistCount: candidate.sharedMusicArtistCount,
                      sharedPlaylistTrackCount:
                          candidate.sharedMusicPlaylistTrackCount,
                    ),
                    if (candidate.sharedMusicTracks.isNotEmpty ||
                        candidate.sharedMusicArtists.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l10n.musicSharedCounts(
                          candidate.sharedMusicTrackCount ??
                              candidate.sharedMusicTracks.length,
                          candidate.sharedMusicArtistCount ??
                              candidate.sharedMusicArtists.length,
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                  if (candidate.relationshipCompatibilityScore != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    RelationshipCompatibilityBadge(
                      score: candidate.relationshipCompatibilityScore!,
                      compact: false,
                      showAccent: true,
                    ),
                    if (candidate.relationshipSharedViewCount != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l10n.relationshipSharedViews(
                          candidate.relationshipSharedViewCount!,
                        ),
                      ),
                    ],
                    if (candidate.relationshipSummaryTopics.isNotEmpty)
                      Text(
                        relationshipTopicSummary(
                          l10n,
                          relationshipTopicsFromNames(
                            candidate.relationshipSummaryTopics,
                          ),
                        ),
                      ),
                  ],
                  if (candidate.sharedInterests.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      l10n.sharedInterests,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: candidate.sharedInterests
                          .map(
                            (interest) =>
                                MevoraChip(label: interest, compact: true),
                          )
                          .toList(),
                    ),
                  ],
                  if (candidate.compatibilityReasons.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    ...candidate.compatibilityReasons.map(
                      (reason) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                reason,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _relationshipLabel(AppLocalizations l10n, String goal) {
    return switch (goal) {
      'longTerm' => l10n.relationshipGoalLongTerm,
      'casual' => l10n.relationshipGoalCasual,
      'figuringOut' => l10n.relationshipGoalFiguringOut,
      _ => goal,
    };
  }
}

/// Isolated carousel so photo index updates do not rebuild the details list
/// (match watchers / answer streams).
class _DiscoveryPhotoCarousel extends StatefulWidget {
  const _DiscoveryPhotoCarousel({required this.photos});

  final List<String> photos;

  @override
  State<_DiscoveryPhotoCarousel> createState() =>
      _DiscoveryPhotoCarouselState();
}

class _DiscoveryPhotoCarouselState extends State<_DiscoveryPhotoCarousel> {
  late final PageController _pageController = PageController();
  int _photoIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPhotoChanged(int index) {
    // #region agent log
    try {
      final entry = <String, Object?>{
        'sessionId': '80971b',
        'runId': 'post-fix',
        'hypothesisId': 'H5',
        'location': 'discovery_profile_details_page.dart',
        'message': 'photo_page_changed',
        'data': <String, Object?>{
          'index': index,
          'total': widget.photos.length,
        },
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      // ignore: avoid_print
      print('[PHOTO_DEBUG] ${jsonEncode(entry)}');
    } on Object {
      // Ignore.
    }
    // #endregion
    setState(() => _photoIndex = index);
    final photos = widget.photos;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth =
        (MediaQuery.sizeOf(context).width * dpr).round().clamp(320, 1080);
    if (index + 1 < photos.length) {
      DiscoveryNetworkImage.prefetch(photos[index + 1], cacheWidth: cacheWidth);
    }
    if (index > 0) {
      DiscoveryNetworkImage.prefetch(photos[index - 1], cacheWidth: cacheWidth);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final photos = widget.photos;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.55,
      ),
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (photos.isEmpty)
                  ColoredBox(
                    color: theme.colorScheme.primaryContainer,
                    child: Icon(
                      Icons.person_outline,
                      size: 72,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  )
                else
                  PageView.builder(
                    controller: _pageController,
                    itemCount: photos.length,
                    // Load neighbors only after swipe; preloading full pending
                    // Storage JPGs hangs the carousel on flaky networks.
                    allowImplicitScrolling: false,
                    onPageChanged: _onPhotoChanged,
                    itemBuilder: (context, index) {
                      return DiscoveryNetworkImage(url: photos[index]);
                    },
                  ),
                if (photos.length > 1)
                  Positioned(
                    top: AppSpacing.sm,
                    right: AppSpacing.sm,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        child: Text(
                          l10n.photoCounter(_photoIndex + 1, photos.length),
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
