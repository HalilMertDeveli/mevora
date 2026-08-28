import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_display_status.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/presentation/pages/discovery_profile_details_page.dart';
import 'package:mevora/features/matching/domain/models/incoming_likes.dart';
import 'package:mevora/features/matching/presentation/controllers/incoming_likes_controller.dart';
import 'package:mevora/features/matching/presentation/widgets/likes_you_insight_card.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

/// Premium-gated admirers list.
///
/// Free: anonymous blur cards from [IncomingLikesSnapshot.count] only — never
/// real names/photos (those are not sent by the server).
/// Premium: real liker previews; tap opens profile details.
class LikesYouPage extends StatefulWidget {
  const LikesYouPage({super.key});

  @override
  State<LikesYouPage> createState() => _LikesYouPageState();
}

class _LikesYouPageState extends State<LikesYouPage> {
  IncomingLikesController? _controller;
  String? _boundUid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final social = SocialScope.maybeOf(context);
    final uid = AuthScope.maybeOf(context)?.user?.id ?? social?.uidSource.currentUid;
    if (social == null) {
      return;
    }
    if (_controller != null && _boundUid == uid) {
      return;
    }
    _controller?.dispose();
    _boundUid = uid;
    _controller = IncomingLikesController(
      repository: social.incomingLikesRepository,
    )..load();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final l10n = AppLocalizations.of(context);
    if (controller == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.likesYouTitle)),
        body: MevoraEmptyState(message: l10n.needSignIn),
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.likesYouTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  l10n.likesYouEntrySubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          body: controller.loading
              ? MevoraLoading.page(message: l10n.likesYouTitle)
              : controller.error != null
              ? MevoraErrorView(
                  message: l10n.likesYouLoadError,
                  onRetry: controller.load,
                )
              : controller.snapshot.locked || controller.snapshot.premiumRequired
              ? _LockedLikesBody(
                  count: controller.snapshot.count,
                  onUpgrade: () => context.push(AppRoutes.boost),
                )
              : controller.snapshot.items.isEmpty
              ? MevoraEmptyState(
                  icon: Icons.insights_outlined,
                  title: l10n.likesYouEmptyTitle,
                  message: l10n.likesYouEmptyMessage,
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  itemCount: controller.snapshot.items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final item = controller.snapshot.items[index];
                    return LikesYouInsightCard(
                      item: item,
                      onTap: () => _openPremiumProfile(context, item),
                      onConnect: () => _openPremiumProfile(context, item),
                    );
                  },
                ),
        );
      },
    );
  }

  Future<void> _openPremiumProfile(
    BuildContext context,
    IncomingLikerPreview item,
  ) async {
    final candidate = DiscoveryCandidate(
      uid: item.uid,
      displayName: item.displayName,
      age: item.age ?? 0,
      photos: [
        if (item.photoUrl != null && item.photoUrl!.isNotEmpty) item.photoUrl!,
      ],
      city: item.city,
      compatibilityStatus: CompatibilityDisplayStatus.ready,
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DiscoveryProfileDetailsPage(candidate: candidate),
      ),
    );
  }
}

class _LockedLikesBody extends StatelessWidget {
  const _LockedLikesBody({required this.count, required this.onUpgrade});

  final int count;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final placeholders = count.clamp(0, 12);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        MevoraCard(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.softGreen.withValues(alpha: 0.14),
                    border: Border.all(
                      color: AppColors.softGreen.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    color: AppColors.softGreen,
                    size: 28,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  count > 0
                      ? l10n.likesYouLockedCount(count)
                      : l10n.likesYouLockedTitle,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.likesYouLockedMessage,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                MevoraButton(
                  label: l10n.likesYouUnlockCta,
                  onPressed: onUpgrade,
                ),
              ],
            ),
          ),
        ),
        if (placeholders > 0) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.likesYouBlurredHint,
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          ...List.generate(
            placeholders,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: _BlurredLikerCard(onUpgrade: onUpgrade),
            ),
          ),
        ],
      ],
    );
  }
}

/// Anonymous card — no network image, no name, no uid.
class _BlurredLikerCard extends StatelessWidget {
  const _BlurredLikerCard({required this.onUpgrade});

  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return MevoraCard(
      onTap: onUpgrade,
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: CircleAvatar(
              radius: 26,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.person,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        title: Text(
          l10n.likesYouHiddenName,
          style: theme.textTheme.titleMedium,
        ),
        subtitle: Text(l10n.likesYouHiddenSubtitle),
        trailing: Icon(
          Icons.lock_outline,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
