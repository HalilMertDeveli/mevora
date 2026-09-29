import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
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
import 'package:mevora/shared/animations/mevora_page_transitions.dart';
import 'package:mevora/shared/art/mevora_spot.dart';
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
    final uid =
        AuthScope.maybeOf(context)?.user?.id ?? social?.uidSource.currentUid;
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
                  style: Theme.of(context).textTheme.bodySmall,
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
              : controller.snapshot.locked ||
                    controller.snapshot.premiumRequired
              ? _LockedLikesBody(
                  count: controller.snapshot.count,
                  onUpgrade: () => context.push(AppRoutes.premium),
                )
              : controller.snapshot.items.isEmpty
              ? MevoraEmptyState(
                  art: MevoraArt.emptyLikes,
                  title: l10n.likesYouEmptyTitle,
                  message: l10n.likesYouEmptyMessage,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    AppSpacing.sm,
                    AppSpacing.screenPadding,
                    AppSpacing.xl,
                  ),
                  itemCount: controller.snapshot.items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final item = controller.snapshot.items[index];
                    return LikesYouInsightCard(
                      item: item,
                      breakdown: item.breakdown,
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
      MevoraPageTransitions.route<void>(
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
    final p = context.palette;
    final placeholders = count.clamp(0, 6);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.md,
        AppSpacing.screenPadding,
        AppSpacing.xl,
      ),
      children: [
        if (placeholders > 0) ...[
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: 3 / 4,
            children: [
              for (var i = 0; i < placeholders; i++)
                _HiddenLiker(onTap: onUpgrade, index: i),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        MevoraCard(
          color: p.premiumSurface,
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              Icon(MevoraIcons.locked, color: p.premium, size: 28),
              const SizedBox(height: AppSpacing.s12),
              Text(
                count > 0
                    ? l10n.likesYouLockedCount(count)
                    : l10n.likesYouLockedTitle,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: p.onPremiumSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.likesYouLockedMessage,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: p.onPremiumSurface.withValues(alpha: 0.8),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              MevoraButton(
                label: l10n.likesYouUnlockCta,
                icon: MevoraIcons.premiumActive,
                variant: MevoraButtonVariant.inverse,
                onPressed: onUpgrade,
              ),
            ],
          ),
        ),
        if (placeholders > 0) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.likesYouBlurredHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

/// An anonymous tile — no network image, no name, no uid. Just the shape of
/// someone waiting, in one of Mevora's warm tints.
class _HiddenLiker extends StatelessWidget {
  const _HiddenLiker({required this.onTap, required this.index});

  final VoidCallback onTap;
  final int index;

  static const _tints = [
    AppColors.emberSoft,
    AppColors.sageSoft,
    AppColors.duskSoft,
    AppColors.marigoldSoft,
    AppColors.roseSoft,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = context.palette;
    return Semantics(
      button: true,
      label: '${l10n.likesYouHiddenName}. ${l10n.likesYouHiddenSubtitle}',
      excludeSemantics: true,
      child: Material(
        color: _tints[index % _tints.length],
        borderRadius: BorderRadius.circular(AppRadii.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Center(
                child: Icon(
                  MevoraIcons.profileActive,
                  size: 40,
                  color: p.textPrimary.withValues(alpha: 0.12),
                ),
              ),
              Positioned(
                right: AppSpacing.sm,
                bottom: AppSpacing.sm,
                child: Icon(
                  MevoraIcons.locked,
                  size: 16,
                  color: p.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
